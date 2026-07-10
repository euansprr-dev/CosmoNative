// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeView.swift
// Idea Focus Mode v2 — Greenhouse clean.
// June 2026 rewrite: floating glass toolbar (status, client, Begin Writing,
// inspector toggle), centered manuscript column (the only serifs are the
// idea's own title and body), and a structured right inspector for swipes /
// framework / blueprint / research. Replaces the Atelier marginalia gutter.
// Editors live in IdeaManuscriptEditors.swift; intelligence panels in
// IdeaInspectorView.swift; chrome state in IdeaWorkspaceModel.swift.

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Idea Focus Mode View

struct IdeaFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @State private var viewModel: IdeaFocusModeViewModel
    @State private var workspace = IdeaWorkspaceModel()
    @State private var newHookText: String = ""
    /// The view OWNS its context provider — the editable-surface registry holds
    /// it weakly; the old single global slot deallocated it on any other view's
    /// registration, unbinding this surface from the assistant.
    @State private var ownedContextProvider: IdeaContextProvider?
    @State private var isPromoting: Bool = false
    @State private var showProfileEditor: Bool = false
    @State private var showBlueprintPicker: Bool = false
    @State private var isLoadingArcRecs: Bool = false
    @State private var showBlueprintSheet: Bool = false
    @State private var showResearchSheet: Bool = false
    @State private var showFrameworkSheet: Bool = false
    @State private var atelierScrollMetrics = CortexScrollMetrics()
    @State private var bodyReviewProposal: CosmoAssistantProposal?
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContextFocused: Bool
    @FocusState private var focusedHookEditor: HookEditorFocus?
    @FocusState private var focusedOutlineSlideID: UUID?

    /// The idea's own accent — used sparingly for the focus rule.
    private let ideaAccent = DS.entityIdea

    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _viewModel = State(initialValue: IdeaFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            workspaceLayout
            overlayPresentations
        }
        .background(DS.bg.ignoresSafeArea())
        .background {
            FocusModeEditorBlurClickMonitor {
                clearManuscriptEditingFocus()
            }
        }
        .cosmoSurfaceKeyWindowActivation(surfaceID: "idea:\(atom.uuid)")
        .focusImmersiveEntryTransition()
        .onAppear(perform: handleAppear)
        .onChange(of: isPaneContextOwner) { _, isOwner in
            if isOwner { registerContextProvider() }
        }
        .onReceive(CosmoInlineAssistantStore.shared.$proposals) { proposals in
            let surfaceID = "idea:\(atom.uuid)"
            bodyReviewProposal = proposals.last { proposal in
                proposal.surfaceID == surfaceID && proposal.hasReviewableOperations
            }
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            viewModel.saveOnClose()
        }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress { handleKeyCommand($0) }
        .overlay { profileEditorOverlay }
        .sheet(isPresented: $showBlueprintSheet) { atelierBlueprintSheet }
        .sheet(isPresented: $showResearchSheet) { atelierResearchSheet }
        .sheet(isPresented: $showFrameworkSheet) { atelierFrameworkSheet }
        .onChange(of: viewModel.researchResults) { _, _ in viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.arcRecommendations) { _, _ in viewModel.scheduleAutoSave() }
        .onChange(of: viewModel.chatHistory) { _, _ in viewModel.scheduleAutoSave() }
    }

    // MARK: - Layout

    private var workspaceLayout: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                centerColumn
                if workspace.breakpoint == .regular, workspace.isInspectorVisible {
                    Divider().overlay(DS.borderSubtle)
                    inspector
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(ProMotionSprings.focusTransition, value: workspace.isInspectorVisible)
            .overlay(alignment: .trailing) { inspectorOverlay }
            .onChange(of: geometry.size.width, initial: true) { _, width in
                let resolved = IdeaWorkspaceBreakpoint(width: width)
                if workspace.breakpoint != resolved {
                    workspace.breakpoint = resolved
                }
            }
        }
    }

    private var centerColumn: some View {
        ScrollView {
            manuscriptColumn
                .padding(.horizontal, DS.space24)
                .padding(.top, DS.space16)
                .padding(.bottom, DS.space48)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(
                    CortexScrollViewIntrospector { metrics in
                        if metrics != atelierScrollMetrics {
                            atelierScrollMetrics = metrics
                        }
                    }
                )
        }
        .scrollIndicators(.hidden)
        .cortexThinScrollbar(metrics: atelierScrollMetrics)
        .scrollEdgeEffectStyle(.soft, for: .all)
        .safeAreaInset(edge: .top, spacing: 0) {
            IdeaWorkspaceToolbar(
                viewModel: viewModel,
                workspace: workspace,
                isPaneContext: isPaneContext,
                isPromoting: isPromoting,
                actions: workspaceActions
            )
            .padding(.horizontal, DS.space16)
            .padding(.top, DS.space10)
            .padding(.bottom, DS.space6)
        }
    }

    private var inspector: some View {
        IdeaInspectorView(
            viewModel: viewModel,
            isLoadingArcRecommendations: isLoadingArcRecs,
            actions: workspaceActions
        )
    }

    /// Compact widths: the inspector covers the manuscript, so it's opt-in.
    @ViewBuilder
    private var inspectorOverlay: some View {
        if workspace.breakpoint == .compact, workspace.isInspectorOverlayPresented {
            inspector
                .overlay(alignment: .leading) {
                    Divider().overlay(DS.borderSubtle)
                }
                .shadow(color: .black.opacity(0.18), radius: 18, x: -6)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(2)
        }
    }

    private var workspaceActions: IdeaWorkspaceActions {
        IdeaWorkspaceActions(
            onShowLinkSwipes: { viewModel.showLinkSwipesOverlay = true },
            onSuggestFramework: {
                refreshArcRecommendations()
                showFrameworkSheet = true
            },
            onChangeFramework: { showFrameworkSheet = true },
            onShowBlueprintSheet: { showBlueprintSheet = true },
            onShowBlueprintPicker: { showBlueprintPicker = true },
            onShowResearch: { showResearchSheet = true },
            onOpenAtomInPane: { openAtomInPane($0) },
            onShowProfileEditor: { showProfileEditor = true },
            onBeginWriting: beginWriting,
            onClose: onClose
        )
    }

    // MARK: - Lifecycle

    private func handleAppear() {
        AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
        registerContextProvider()
    }

    private func registerContextProvider() {
        guard !isPaneContext || isPaneContextOwner else { return }
        let provider = IdeaContextProvider(atom: atom, viewModel: viewModel)
        ownedContextProvider = provider
        CosmoWindowViewModel.shared.updateContext(provider: provider)
    }

    // MARK: - Keyboard

    private func handleEscape() -> KeyPress.Result {
        if viewModel.showMentionOverlay {
            viewModel.showMentionOverlay = false
            viewModel.mentionSearchText = ""
            return .handled
        }
        if showBlueprintPicker {
            showBlueprintPicker = false
            return .handled
        }
        if viewModel.showLinkSwipesOverlay {
            viewModel.showLinkSwipesOverlay = false
            return .handled
        }
        if viewModel.showLinkConnectionsOverlay {
            viewModel.showLinkConnectionsOverlay = false
            return .handled
        }
        if workspace.isInspectorOverlayPresented {
            withAnimation(ProMotionSprings.focusTransition) {
                workspace.isInspectorOverlayPresented = false
            }
            return .handled
        }
        onClose()
        return .handled
    }

    private func handleKeyCommand(_ keyPress: KeyPress) -> KeyPress.Result {
        guard keyPress.modifiers.contains(.command),
              keyPress.modifiers.contains(.option),
              keyPress.key == KeyEquivalent("i") else { return .ignored }
        withAnimation(ProMotionSprings.focusTransition) {
            workspace.toggleInspector()
        }
        return .handled
    }

    // MARK: - Actions

    private func beginWriting() {
        let isBodyEmpty = viewModel.editableBody
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !isPromoting, !isBodyEmpty else { return }
        isPromoting = true
        Task {
            await viewModel.promoteToContent()
            isPromoting = false
        }
    }

    private func openAtomInPane(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
    }

    private func refreshArcRecommendations() {
        isLoadingArcRecs = true
        viewModel.arcRecommendations = []
        viewModel.scheduleAutoSave()
        Task {
            await viewModel.generateArcRecommendations()
            isLoadingArcRecs = false
        }
    }

    // MARK: - Marginalia sheets

    @ViewBuilder
    private var atelierBlueprintSheet: some View {
        VStack(spacing: 0) {
            AtelierSheetHeader(title: "BLUEPRINT") { showBlueprintSheet = false }
            if let blueprint = viewModel.selectedBlueprint {
                BlueprintDisplayView(blueprintAtom: blueprint)
                    .padding(DS.space24)
            } else {
                Text("No blueprint selected")
                    .font(DS.callout)
                    .foregroundStyle(DS.textMuted)
                    .padding(DS.space48)
            }
        }
        .frame(width: 720, height: 640)
        .background(DS.bg)
    }

    @ViewBuilder
    private var atelierResearchSheet: some View {
        VStack(spacing: 0) {
            AtelierSheetHeader(title: "RESEARCH") { showResearchSheet = false }
            IdeaResearchPanel(
                results: Bindable(viewModel).researchResults,
                ideaText: viewModel.editableBody,
                clientNiche: viewModel.linkedClient?.title
            )
            .padding(DS.space24)
        }
        .frame(width: 720, height: 640)
        .background(DS.bg)
    }

    @ViewBuilder
    private var atelierFrameworkSheet: some View {
        VStack(spacing: 0) {
            AtelierSheetHeader(title: "FRAMEWORK") { showFrameworkSheet = false }

            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    if isLoadingArcRecs {
                        HStack(spacing: DS.space8) {
                            ProgressView().controlSize(.small)
                            Text("Reading the idea…")
                                .font(DS.callout)
                                .foregroundStyle(DS.textMuted)
                        }
                    } else if viewModel.arcRecommendations.isEmpty {
                        Text("Add more context to get framework suggestions.")
                            .font(DS.callout)
                            .foregroundStyle(DS.textMuted)
                    } else {
                        ForEach(viewModel.arcRecommendations) { rec in
                            atelierFrameworkRow(rec)
                        }
                    }
                }
                .padding(DS.space24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 560, height: 540)
        .background(DS.bg)
    }

    private func atelierFrameworkRow(_ rec: ArcRecommendation) -> some View {
        let isSelected = viewModel.selectedArcType == rec.arcName
        return Button {
            viewModel.selectedArcType = rec.arcName
            viewModel.scheduleAutoSave()
        } label: {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space8) {
                    Text(rec.arcName)
                        .font(DS.headline)
                        .foregroundStyle(DS.text)
                    Text("\(Int(rec.confidence * 100))%")
                        .font(DS.caption.monospacedDigit())
                        .foregroundStyle(DS.textMuted)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(DS.caption.weight(.semibold))
                            .foregroundStyle(DS.accent)
                            .accessibilityHidden(true)
                    }
                }
                Text(rec.explanation)
                    .font(DS.callout)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(3)
                Divider().overlay(DS.borderSubtle)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Overlay Presentations

    @ViewBuilder
    private var overlayPresentations: some View {
        if viewModel.showLinkSwipesOverlay {
            LinkSwipesOverlay(
                viewModel: viewModel,
                isPresented: Bindable(viewModel).showLinkSwipesOverlay
            )
            .transition(.opacity)
            .zIndex(100)
        }

        if viewModel.showLinkConnectionsOverlay {
            LinkConnectionsOverlay(
                viewModel: viewModel,
                isPresented: Bindable(viewModel).showLinkConnectionsOverlay
            )
            .transition(.opacity)
            .zIndex(100)
        }

        if showBlueprintPicker {
            LinkSwipesOverlay(
                viewModel: viewModel,
                isPresented: $showBlueprintPicker,
                blueprintMode: true
            )
            .transition(.opacity)
            .zIndex(100)
        }
    }

    @ViewBuilder
    private var profileEditorOverlay: some View {
        if showProfileEditor {
            ZStack {
                FloatingOverlayBackdrop { showProfileEditor = false }
                SanctuarySettingsView(
                    onClose: { showProfileEditor = false },
                    launchStudio: .create,
                    onProfileCreated: { newProfile in
                        Task { await viewModel.assignClient(newProfile) }
                        Task { await viewModel.loadClientProfiles() }
                    }
                )
                .settingsGlassPanel()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

// MARK: - Manuscript Column

extension IdeaFocusModeView {
    /// The centered manuscript — title hero, context editor, hooks, outline.
    /// Content is the hero: no card chrome, hairline dividers carry structure.
    private var manuscriptColumn: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            titleHero
            contextEditor
            hooksSection
            outlineSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(manuscriptWhitespaceBlurLayer)
    }

    private var manuscriptWhitespaceBlurLayer: some View {
        DS.bg.opacity(0.001)
            .contentShape(Rectangle())
            .onTapGesture {
                clearManuscriptEditingFocus()
            }
            .accessibilityHidden(true)
    }

    private func clearManuscriptEditingFocus() {
        isTitleFocused = false
        isContextFocused = false
        focusedHookEditor = nil
        focusedOutlineSlideID = nil
        FocusModeEditorBlur.clearFirstResponder()
    }

    private func sectionLabel(_ title: String) -> some View {
        HStack(spacing: DS.space12) {
            Text(title)
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)
                .fixedSize()
            Divider().overlay(DS.borderSubtle)
        }
        .frame(height: 12)
    }

    // MARK: Title hero

    private var titleHero: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("IDEA · \(viewModel.selectedStatus.rawValue.uppercased())")
                .font(DS.smallCaps)
                .tracking(1.4)
                .foregroundStyle(DS.textMuted)

            TextField("Untitled idea", text: Bindable(viewModel).editableTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.displaySerif)
                .foregroundStyle(DS.text)
                .tracking(-0.5)
                .lineLimit(1...3)
                .focused($isTitleFocused)
                .onChange(of: viewModel.editableTitle) { _, _ in
                    viewModel.scheduleAutoSave()
                }
                .accessibilityLabel("Idea title")

            HStack(spacing: DS.space6) {
                Text(formattedCreatedDate)
                Text("·").accessibilityHidden(true)
                Text(viewModel.selectedFormat?.rawValue.capitalized ?? "Unformatted")
                if let client = viewModel.linkedClient {
                    Text("·").accessibilityHidden(true)
                    Text(client.title ?? "Client")
                }
            }
            .font(DS.caption)
            .foregroundStyle(DS.textMuted)
        }
    }

    private var formattedCreatedDate: String {
        guard let date = ISO8601.date(from: viewModel.idea.createdAt) else {
            return "Undated"
        }
        return CosmoDateFormatters.monthDay.string(from: date)
    }

    // MARK: Context editor — chromeless manuscript

    private var contextEditor: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            contextMentionChips

            if let review = bodyReviewProposal {
                // Inline assistant review: the manuscript becomes the diff until
                // every change is accepted or rejected — same surface, same type.
                CosmoInlineDiffReviewView(
                    store: CosmoInlineAssistantStore.shared,
                    proposal: review,
                    sourceText: viewModel.editableBody,
                    bodyFont: .system(size: 17, weight: .regular, design: .serif),
                    textColor: DS.text
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
            } else {
                contextEditingSurface
            }
        }
    }

    private var contextEditingSurface: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            ZStack(alignment: .topLeading) {
                if viewModel.editableBody.isEmpty {
                    Text("What's the angle?")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.textMuted)
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }

                IdeaContextTextEditor(
                    text: Bindable(viewModel).editableBody,
                    isFocused: $isContextFocused
                ) { newValue in
                    viewModel.scheduleAutoSave()
                    viewModel.autoEnrich()
                    handleMentionTrigger(newValue)
                }
                .frame(maxWidth: .infinity, minHeight: IdeaContextTextView.minimumHeight, alignment: .topLeading)
                .accessibilityLabel("Idea context and direction")
            }
            .overlay(alignment: .leading) {
                // Focus rule — the only affordance. Slides in from -12 on focus.
                Rectangle()
                    .fill(ideaAccent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
                    .opacity(isContextFocused ? 1 : 0)
                    .offset(x: isContextFocused ? -12 : -24)
                    .animation(ProMotionSprings.snappy, value: isContextFocused)
            }
            .overlay(alignment: .topLeading) { mentionOverlay }
        }
    }

    @ViewBuilder
    private var mentionOverlay: some View {
        if viewModel.showMentionOverlay {
            CosmoMentionOverlay(
                isVisible: Bindable(viewModel).showMentionOverlay,
                searchText: Bindable(viewModel).mentionSearchText,
                onSelect: { mentioned in
                    // Truncate the "@query" BEFORE addMention schedules
                    // the autosave, so the snapshot captures the final body.
                    if let atIndex = viewModel.editableBody.lastIndex(of: "@") {
                        viewModel.editableBody = String(viewModel.editableBody[viewModel.editableBody.startIndex..<atIndex])
                    }
                    viewModel.addMention(mentioned)
                },
                onDismiss: {
                    viewModel.showMentionOverlay = false
                    viewModel.mentionSearchText = ""
                }
            )
            .frame(width: 360)
            .frame(maxHeight: 340)
            .offset(y: 28)
            .transition(.opacity.combined(with: .move(edge: .top)))
            .zIndex(10)
        }
    }

    private func handleMentionTrigger(_ newValue: String) {
        if newValue.hasSuffix("@") && !viewModel.showMentionOverlay {
            withAnimation(ProMotionSprings.snappy) {
                viewModel.showMentionOverlay = true
                viewModel.mentionSearchText = ""
            }
        }
        if viewModel.showMentionOverlay {
            if let atIndex = newValue.lastIndex(of: "@") {
                let afterAt = String(newValue[newValue.index(after: atIndex)...])
                viewModel.mentionSearchText = afterAt
            }
        }
    }

    @ViewBuilder
    private var contextMentionChips: some View {
        if !viewModel.mentionedAtoms.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space6) {
                    ForEach(viewModel.mentionedAtoms, id: \.uuid) { mentioned in
                        contextMentionChip(mentioned)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private func contextMentionChip(_ mentioned: Atom) -> some View {
        let entityType = EntityType(rawValue: mentioned.type.rawValue) ?? .idea
        let chipColor = CosmoMentionColors.color(for: entityType)
        return HStack(spacing: DS.space4) {
            Image(systemName: mentioned.type.iconName)
                .font(DS.caption2)
                .accessibilityHidden(true)
            Text(mentioned.title ?? "Untitled")
                .font(DS.caption)
                .lineLimit(1)
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.removeMention(mentioned)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.bold))
                    .foregroundStyle(chipColor.opacity(0.5))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove mention \(mentioned.title ?? "untitled")")
        }
        .foregroundStyle(chipColor.opacity(0.85))
        .padding(.horizontal, DS.space6)
        .padding(.vertical, 2)
        .background(chipColor.opacity(0.08), in: Capsule())
    }
}

// MARK: - Hooks Section

extension IdeaFocusModeView {
    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            sectionLabel("HOOKS")

            VStack(alignment: .leading, spacing: DS.space10) {
                ForEach(Array(viewModel.editableHooks.enumerated()), id: \.offset) { index, hook in
                    hookRow(hook, at: index)
                }
                addHookRow
            }
            .padding(.horizontal, DS.space4)
        }
    }

    private func hookRow(_ hook: String, at index: Int) -> some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Text(romanNumeral(for: index + 1) + ".")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 3)

            HookLineEditor(
                text: hookBinding(at: index),
                editorID: .existing(index),
                focusedEditor: $focusedHookEditor,
                placeholder: "hook",
                font: hookEditorFont(),
                textColor: NSColor(DS.text),
                placeholderColor: NSColor(DS.textMuted.opacity(0.55)),
                onReturn: finishHookEditing,
                onDeleteEmpty: {
                    guard viewModel.editableHooks.indices.contains(index) else { return false }
                    withAnimation(ProMotionSprings.snappy) {
                        focusedHookEditor = nil
                        viewModel.editableHooks.remove(at: index)
                        viewModel.scheduleAutoSave()
                    }
                    return true
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: DS.space8)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    focusedHookEditor = nil
                    viewModel.editableHooks.remove(at: index)
                    viewModel.scheduleAutoSave()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove hook")
            .padding(.top, 2)
        }
    }

    private var addHookRow: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            Text("+")
                .font(DS.caption.monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .frame(width: 28, alignment: .leading)
                .padding(.top, 3)

            HookLineEditor(
                text: $newHookText,
                editorID: .draft,
                focusedEditor: $focusedHookEditor,
                placeholder: "Add a hook to test the angle",
                font: hookEditorFont(italic: true),
                textColor: NSColor(DS.textSecondary),
                placeholderColor: NSColor(DS.textMuted.opacity(0.65)),
                onReturn: addHook,
                onDeleteEmpty: { false }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("New hook text")
        }
        .padding(.top, DS.space4)
    }

    private func hookBinding(at index: Int) -> Binding<String> {
        Binding(
            get: {
                guard viewModel.editableHooks.indices.contains(index) else { return "" }
                return viewModel.editableHooks[index]
            },
            set: { newValue in
                guard viewModel.editableHooks.indices.contains(index) else { return }
                viewModel.editableHooks[index] = newValue
                viewModel.scheduleAutoSave()
            }
        )
    }

    private func hookEditorFont(italic: Bool = false) -> NSFont {
        let font = NSFont.systemFont(ofSize: 15)
        guard italic else { return font }
        return NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    private func finishHookEditing() {
        focusedHookEditor = nil
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    private func romanNumeral(for value: Int) -> String {
        let numerals: [(Int, String)] = [
            (10, "x"), (9, "ix"), (5, "v"), (4, "iv"), (1, "i")
        ]
        var result = ""
        var n = value
        for (val, letters) in numerals {
            while n >= val {
                result += letters
                n -= val
            }
        }
        return result.isEmpty ? "\(value)" : result
    }

    private func addHook() {
        let trimmed = newHookText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            viewModel.editableHooks.append(trimmed)
            newHookText = ""
            focusedHookEditor = nil
            viewModel.scheduleAutoSave()
        }
    }
}

// MARK: - Outline Section (simple mode only)

extension IdeaFocusModeView {
    @ViewBuilder
    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            outlineHeader

            if let outline = viewModel.codexOutline {
                outlineSlides(outline)
            }
        }
        .onAppear {
            if viewModel.codexOutline == nil {
                viewModel.replaceCodexOutline(CodexOutlineModel(arcShape: nil, slides: [
                    CodexOutlineSlide(id: UUID(), position: 1, speechAct: nil,
                        readerDeltas: [], frame: nil, distance: nil,
                        techniques: [], transition: nil, note: nil)
                ]))
            }
        }
    }

    private var outlineHeader: some View {
        HStack(spacing: DS.space12) {
            sectionLabel("OUTLINE")

            Button { addNewSlide() } label: {
                Label("Slide", systemImage: "plus")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Add a slide")
            .accessibilityLabel("Add slide")
        }
    }

    private func outlineSlides(_ outline: CodexOutlineModel) -> some View {
        VStack(alignment: .leading, spacing: IdeaOutlineLayoutMetrics.normalRowSpacing) {
            ForEach(outline.slides) { slide in
                outlineSlideRow(slide)
            }
        }
        .padding(.horizontal, DS.space4)
    }

    private func outlineSlideRow(_ slide: CodexOutlineSlide) -> some View {
        HStack(alignment: .top, spacing: DS.space16) {
            Text(romanNumeral(for: slide.position))
                .font(DS.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(DS.textMuted)
                .frame(width: 36, height: IdeaOutlineLayoutMetrics.minimumEditorHeight, alignment: .topLeading)

            OutlineSlideNoteEditor(
                text: slideNoteBinding(for: slide.id),
                slideID: slide.id,
                focusedSlideID: $focusedOutlineSlideID,
                placeholder: "what should this slide do?",
                onReturn: { insertSlideAfterFocusedSlide(slide.id) },
                onMoveFocus: { direction in
                    focusAdjacentOutlineSlide(from: slide.id, direction: direction)
                },
                onDeleteEmpty: { handleDeleteOnSlide(slide.id) == .handled }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)

            Button { removeSlide(slide.id) } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2.weight(.medium))
                    .foregroundStyle(DS.textMuted.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove slide \(slide.position)")
        }
    }

    private func slideNoteBinding(for slideId: UUID) -> Binding<String> {
        Binding(
            get: {
                viewModel.codexOutline?.slides.first(where: { $0.id == slideId })?.note ?? ""
            },
            set: { newValue in
                viewModel.updateOutlineSlideNote(slideId: slideId, note: newValue)
            }
        )
    }

    // MARK: Outline Mutations

    private func addNewSlide() {
        guard var outline = viewModel.codexOutline else { return }
        _ = CodexOutlineEditing.insertSlide(after: outline.slides.last?.id ?? UUID(), in: &outline)
        viewModel.replaceCodexOutline(outline)
    }

    private func removeSlide(_ id: UUID) {
        guard var outline = viewModel.codexOutline else { return }
        outline.slides.removeAll { $0.id == id }
        CodexOutlineEditing.renumberSlides(in: &outline)
        viewModel.replaceCodexOutline(outline)
    }

    private func insertSlideAfterFocusedSlide(_ slideID: UUID) {
        guard var outline = viewModel.codexOutline else { return }
        let newID = CodexOutlineEditing.insertSlide(after: slideID, in: &outline)
        viewModel.replaceCodexOutline(outline)
        focusOutlineSlide(newID)
    }

    private func handleDeleteOnSlide(_ slideID: UUID) -> KeyPress.Result {
        guard var outline = viewModel.codexOutline,
              let previousID = CodexOutlineEditing.removeSlideIfEmpty(slideID, in: &outline) else {
            return .ignored
        }

        viewModel.replaceCodexOutline(outline)
        focusOutlineSlide(previousID)
        return .handled
    }

    private func focusOutlineSlide(_ slideID: UUID) {
        DispatchQueue.main.async {
            focusedOutlineSlideID = nil
            focusedOutlineSlideID = slideID
            OutlineSlideFocusRegistry.shared.requestFocus(slideID)
        }
    }

    private func focusAdjacentOutlineSlide(from slideID: UUID, direction: OutlineSlideNavigationDirection) {
        guard let slides = viewModel.codexOutline?.slides,
              let currentIndex = slides.firstIndex(where: { $0.id == slideID }) else { return }

        let targetIndex: Int
        switch direction {
        case .previous:
            targetIndex = currentIndex - 1
        case .next:
            targetIndex = currentIndex + 1
        }

        guard slides.indices.contains(targetIndex) else { return }
        focusOutlineSlide(slides[targetIndex].id)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Idea Focus Mode") {
    IdeaFocusModeView(
        atom: Atom.new(
            type: .idea,
            title: "The Paradox of Productivity",
            body: "Most people optimize for output when they should be optimizing for clarity. The real bottleneck is not time -- it is attention quality."
        ),
        onClose: {}
    )
    .frame(width: 1280, height: 800)
}
#endif

// MARK: - Cosmo Context Provider

@MainActor
class IdeaContextProvider: CosmoContextProvider, CosmoEditableSurfaceProvider {
    private let atom: Atom
    private weak var viewModel: IdeaFocusModeViewModel?

    init(atom: Atom, viewModel: IdeaFocusModeViewModel) {
        self.atom = atom
        self.viewModel = viewModel
    }

    var contextType: CosmoContextType { .ideaFocusMode }

    var surfaceID: String {
        "idea:\(atom.uuid)"
    }

    static func targetID(for atomUUID: String) -> String {
        "idea:\(atomUUID):body"
    }

    func editableSnapshot() -> CosmoEditableSourceSnapshot {
        let body = viewModel?.editableBody ?? atom.body ?? ""
        let hooks = viewModel?.editableHooks ?? []

        // Hooks ride along as anchors so the model can target them with
        // structuredFieldReplacement (anchorID "hook-N") without the hook text
        // living inside the body — body diffs stay locate-exact.
        var anchors: [CosmoEditableAnchor] = [
            .init(id: "body", label: "Idea context", utf16Start: 0, utf16Length: body.utf16.count)
        ]
        for (index, hook) in hooks.enumerated() {
            anchors.append(.init(id: "hook-\(index)", label: hook, utf16Start: 0, utf16Length: 0))
        }

        let title = (viewModel?.editableTitle ?? atom.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return CosmoEditableSourceSnapshot(
            surfaceID: surfaceID,
            targetID: Self.targetID(for: atom.uuid),
            kind: .text,
            title: title.isEmpty ? "Untitled idea" : title,
            text: body,
            sourceHash: CosmoEditableSurfaceHasher.hash(body),
            anchors: anchors
        )
    }

    func apply(operation: CosmoAssistantProposalOperation) async throws -> CosmoEditableOperationResult {
        guard let viewModel else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Idea editor is unavailable"
            )
        }
        guard operation.targetID == Self.targetID(for: atom.uuid) else {
            return CosmoEditableOperationResult(
                operationID: operation.id, status: .conflicted, message: "Target changed"
            )
        }
        return try await viewModel.applyInlineAssistantEdit(operation)
    }

    func reject(operation: CosmoAssistantProposalOperation) async -> CosmoEditableOperationResult {
        CosmoEditableOperationResult(operationID: operation.id, status: .rejected, message: "Rejected")
    }

    var contextSummary: String {
        let status = viewModel?.selectedStatus.rawValue ?? "spark"
        return "Idea: \(atom.title ?? "Untitled") — \(status)"
    }

    var contextData: CosmoContextData {
        var viewData: [String: String] = [:]

        if let vm = viewModel {
            viewData["status"] = vm.selectedStatus.rawValue
            if let format = vm.selectedFormat {
                viewData["format"] = format.rawValue
            }
            if let platform = vm.selectedPlatform {
                viewData["platform"] = platform.rawValue
            }
            if !vm.editableBody.isEmpty {
                viewData["bodyPreview"] = String(vm.editableBody.prefix(500))
            }
            if let insight = vm.insight {
                if let hooks = insight.hookSuggestions, !hooks.isEmpty {
                    viewData["hookCount"] = "\(hooks.count)"
                }
                if let swipes = insight.matchingSwipes, !swipes.isEmpty {
                    viewData["matchedSwipes"] = "\(swipes.count)"
                }
            }
        }

        return CosmoContextData(
            currentAtomUUID: atom.uuid,
            currentAtomType: "idea",
            currentAtomTitle: atom.title,
            viewSpecificData: viewData
        )
    }

    var availableActions: [CosmoWindowAction] {
        guard let viewModel else { return [] }

        return [
            CosmoWindowAction(
                id: "idea-append-body",
                name: "Insert into Body",
                description: "Append text to the current idea body.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing inserted." }
                await MainActor.run {
                    if viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        viewModel.editableBody = trimmed
                    } else {
                        viewModel.editableBody += "\n\n" + trimmed
                    }
                }
                await viewModel.save()
                return "Inserted into the idea body."
            },
            CosmoWindowAction(
                id: "idea-add-hook",
                name: "Add Hook",
                description: "Add a hook line without overwriting existing hooks.",
                modelTier: .balanced
            ) { prompt in
                let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "Nothing added." }
                await MainActor.run {
                    viewModel.editableHooks.append(trimmed)
                }
                await viewModel.save()
                return "Added a hook."
            }
        ]
    }
}
