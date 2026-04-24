// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeView.swift
// The Atelier — manuscript column + marginalia gutter.
// April 2026 — V2 redesign following the Akashic Codex aesthetic.
//
// The idea is a manuscript on vellum. Intelligence is marginalia in the gutter.
// Gilt is ornament, never fill.

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Idea Focus Mode View

/// Full-screen thinking surface for an idea.
/// Centered manuscript column: serif title, chromeless context editor, numbered hooks, outline.
/// Right marginalia gutter: swipes, framework, blueprint, research, cosmo — all quiet, chromeless.
/// Centered gilt-bracketed CTA at the bottom.
struct IdeaFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: IdeaFocusModeViewModel
    @StateObject private var cosmoSession: FocusCosmoSession
    @State private var newHookText: String = ""
    @State private var isPromoting: Bool = false
    @State private var showProfileEditor: Bool = false
    @State private var showBlueprintPicker: Bool = false
    @State private var isLoadingArcRecs: Bool = false
    @State private var outlineAdvancedMode: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var showBlueprintSheet: Bool = false
    @State private var showResearchSheet: Bool = false
    @State private var chatExpanded: Bool = false
    @State private var showFrameworkSheet: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContextFocused: Bool

    // MARK: - Constants

    /// The idea's own accent — used sparingly for the focus rule and interactive states.
    private let ideaAccent = DS.entityIdea

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneContextOwner) private var isPaneContextOwner

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: IdeaFocusModeViewModel(atom: atom))
        _cosmoSession = StateObject(wrappedValue: FocusCosmoSession(
            atomUUID: atom.uuid,
            atomTitle: atom.title,
            contextKind: .idea
        ))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                atelierHeader

                ScrollView {
                    HStack(alignment: .top, spacing: DS.space24) {
                        manuscriptColumn
                            .frame(maxWidth: .infinity, alignment: .leading)
                        marginaliaGutter
                            .frame(width: 220)
                            .padding(.top, 64)
                    }
                    .padding(.horizontal, DS.space24)
                    .padding(.top, DS.space4)
                    .padding(.bottom, DS.space20)
                }
                .scrollIndicators(.hidden)
            }

            overlayPresentations
        }
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            let provider = IdeaContextProvider(atom: atom, viewModel: viewModel)
            if !isPaneContext || isPaneContextOwner {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
            withAnimation(.easeOut(duration: 0.45).delay(0.05)) {
                hasAppeared = true
            }
        }
        .onChange(of: isPaneContextOwner) { _, isOwner in
            if isOwner {
                let provider = IdeaContextProvider(atom: atom, viewModel: viewModel)
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onDisappear {
            AtomRepository.shared.releaseEditingLock(uuid: atom.uuid)
            viewModel.saveOnClose()
        }
        .onKeyPress(.escape) {
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
            onClose()
            return .handled
        }
        .overlay { profileEditorOverlay }
        .sheet(isPresented: $showBlueprintSheet) { atelierBlueprintSheet }
        .sheet(isPresented: $showResearchSheet) { atelierResearchSheet }
        .sheet(isPresented: $showFrameworkSheet) { atelierFrameworkSheet }
    }

    // MARK: - Marginalia sheets

    @ViewBuilder
    private var atelierBlueprintSheet: some View {
        VStack(spacing: 0) {
            AtelierSheetHeader(title: "BLUEPRINT") { showBlueprintSheet = false }
            if let blueprint = viewModel.selectedBlueprint {
                BlueprintDisplayView(
                    blueprintAtom: blueprint,
                    displayMode: $viewModel.blueprintDisplayMode
                )
                .padding(DS.space24)
            } else {
                Text("No blueprint selected")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.inkFaded)
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
                results: $viewModel.researchResults,
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
                            Text("analyzing idea…")
                                .font(DS.dateSerif)
                                .italic()
                                .foregroundStyle(DS.inkFaded)
                        }
                    } else if viewModel.arcRecommendations.isEmpty {
                        Text("add context to get arc suggestions")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded)
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
        } label: {
            VStack(alignment: .leading, spacing: DS.space6) {
                HStack(spacing: DS.space8) {
                    Text(rec.arcName)
                        .font(.system(size: 15, weight: .regular, design: .serif))
                        .foregroundStyle(DS.text)
                    Text("\(Int(rec.confidence * 100)) %")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(DS.inkFaded)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.gilt)
                    }
                }
                Text(rec.explanation)
                    .font(DS.callout)
                    .foregroundStyle(DS.inkFaded)
                    .lineLimit(3)
                Rectangle()
                    .fill(DS.sepiaSubtle)
                    .frame(height: 0.5)
                    .padding(.top, DS.space4)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Overlay Presentations

    @ViewBuilder
    private var overlayPresentations: some View {
        if viewModel.showLinkSwipesOverlay {
            LinkSwipesOverlay(
                viewModel: viewModel,
                isPresented: $viewModel.showLinkSwipesOverlay
            )
            .transition(.opacity)
            .zIndex(100)
        }

        if viewModel.showLinkConnectionsOverlay {
            LinkConnectionsOverlay(
                viewModel: viewModel,
                isPresented: $viewModel.showLinkConnectionsOverlay
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
                ContentProfileEditor(existingAtom: nil, onClose: { showProfileEditor = false }) { newProfile in
                    Task { await viewModel.assignClient(newProfile) }
                    Task { await viewModel.loadClientProfiles() }
                }
                .frame(maxWidth: 600, maxHeight: 720)
                .floatingOverlayPanel()
            }
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }
}

// MARK: - Atelier Header (quiet, no chrome)

extension IdeaFocusModeView {
    /// A whisper-thin nav strip. No filled bar, no divider — the only things present
    /// are a back chevron on the left and a client picker on the right.
    private var atelierHeader: some View {
        HStack(spacing: DS.space12) {
            if !isPaneContext {
                atelierBackButton
            }
            Spacer()
            clientPickerPill
            if isPaneContext {
                atelierCloseButton
            }
        }
        .padding(.horizontal, DS.space20)
        .padding(.vertical, DS.space12)
        .opacity(hasAppeared ? 1 : 0)
    }

    private var atelierBackButton: some View {
        Button(action: onClose) {
            HStack(spacing: DS.space6) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .medium))
                Text("back")
                    .font(DS.dateSerif)
                    .italic()
            }
            .foregroundStyle(DS.inkFaded)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.escape, modifiers: [])
        .accessibilityLabel("Go back")
    }

    private var atelierCloseButton: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.inkFaded)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close pane")
    }

    private var clientPickerPill: some View {
        Menu {
            ForEach(viewModel.clientProfiles, id: \.uuid) { client in
                Button(client.title ?? "Client") {
                    Task { await viewModel.assignClient(client) }
                }
            }
            if viewModel.clientProfiles.isEmpty {
                Text("No client profiles")
            }
            Divider()
            Button {
                showProfileEditor = true
            } label: {
                Label("Create New Profile", systemImage: "plus.circle")
            }
            if viewModel.linkedClient != nil {
                Divider()
                Button(role: .destructive) {
                    Task { await viewModel.assignClient(nil) }
                } label: {
                    Label("Remove Client", systemImage: "xmark.circle")
                }
            }
        } label: {
            clientPickerLabel
        }
        .menuStyle(.borderlessButton)
    }

    @ViewBuilder
    private var clientPickerLabel: some View {
        if let client = viewModel.linkedClient {
            HStack(spacing: DS.space6) {
                Circle()
                    .fill(DS.clientColor(for: client.uuid))
                    .frame(width: 5, height: 5)
                Text(client.title?.lowercased() ?? "client")
                    .font(DS.dateSerif)
                    .italic()
                    .foregroundStyle(DS.inkFaded)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .medium))
                    .foregroundStyle(DS.inkFaded.opacity(0.6))
            }
            .contentShape(Rectangle())
        } else {
            Text("no client")
                .font(DS.dateSerif)
                .italic()
                .foregroundStyle(DS.inkFaded.opacity(0.7))
                .contentShape(Rectangle())
        }
    }

    private var isBodyEmpty: Bool {
        viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Left Column

extension IdeaFocusModeView {
    /// The centered manuscript column — serif title, chromeless editor, numbered hooks,
    /// floating-stanza outline, then the gilt CTA.
    private var manuscriptColumn: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            atelierTitleHero
                .atelierStaggerIn(delay: 0.16, appeared: hasAppeared)

            atelierContextEditor
                .atelierStaggerIn(delay: 0.32, appeared: hasAppeared)

            atelierHooksSection
                .atelierStaggerIn(delay: 0.40, appeared: hasAppeared)

            atelierOutlineSection
                .atelierStaggerIn(delay: 0.48, appeared: hasAppeared)

            atelierCTA
                .padding(.top, DS.space24)
                .atelierStaggerIn(delay: 0.64, appeared: hasAppeared)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Title hero

    private var atelierTitleHero: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text(statusOrnamentLabel)
                .font(DS.smallCaps)
                .tracking(2.2)
                .foregroundStyle(DS.giltMuted)

            TextField("Untitled idea", text: $viewModel.editableTitle, axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.displaySerif)
                .foregroundStyle(DS.text)
                .tracking(-0.5)
                .lineLimit(1...3)
                .focused($isTitleFocused)
                .onChange(of: viewModel.editableTitle) { _ in
                    viewModel.scheduleAutoSave()
                }
                .accessibilityLabel("Idea title")

            HStack(spacing: DS.space8) {
                Text(formattedCreatedDate)
                Text("·")
                Text(viewModel.selectedFormat?.rawValue.lowercased() ?? "unformatted")
                if let client = viewModel.linkedClient {
                    Text("·")
                    Text(client.title?.lowercased() ?? "client")
                }
            }
            .font(DS.dateSerif)
            .italic()
            .foregroundStyle(DS.inkFaded)

            Rectangle()
                .fill(DS.sepiaSubtle)
                .frame(width: 120, height: 0.5)
                .padding(.top, DS.space4)
        }
    }

    private var statusOrnamentLabel: String {
        let status = viewModel.selectedStatus.rawValue.uppercased()
        return "· · · IDEA · \(status) · · ·"
    }

    private var formattedCreatedDate: String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = iso.date(from: atom.createdAt)
            ?? ISO8601DateFormatter().date(from: atom.createdAt)
            ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: date).lowercased()
    }

    // MARK: Context editor — chromeless manuscript

    private var atelierContextEditor: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            contextMentionChips

            ZStack(alignment: .topLeading) {
                if viewModel.editableBody.isEmpty {
                    Text("What's the angle?")
                        .font(.system(size: 17, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(DS.inkFaded.opacity(0.6))
                        .padding(.top, 8)
                        .padding(.leading, 6)
                        .allowsHitTesting(false)
                }

                TextEditor(text: $viewModel.editableBody)
                    .font(.system(size: 17, weight: .regular, design: .serif))
                    .foregroundStyle(DS.text)
                    .lineSpacing(7)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .scrollDisabled(true)
                    .focused($isContextFocused)
                    .frame(minHeight: 200)
                    .onChange(of: viewModel.editableBody) { newValue in
                        viewModel.scheduleAutoSave()
                        viewModel.autoEnrich()
                        handleMentionTrigger(newValue)
                    }
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
            .overlay(alignment: .topLeading) {
                if viewModel.showMentionOverlay {
                    CosmoMentionOverlay(
                        isVisible: $viewModel.showMentionOverlay,
                        searchText: $viewModel.mentionSearchText,
                        onSelect: { mentioned in
                            viewModel.addMention(mentioned)
                            if let atIndex = viewModel.editableBody.lastIndex(of: "@") {
                                viewModel.editableBody = String(viewModel.editableBody[viewModel.editableBody.startIndex..<atIndex])
                            }
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
        return HStack(spacing: 4) {
            Image(systemName: mentioned.type.iconName)
                .font(.system(size: 9))
            Text(mentioned.title ?? "Untitled")
                .font(DS.dateSerif)
                .italic()
                .lineLimit(1)
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.removeMention(mentioned)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(chipColor.opacity(0.5))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(chipColor.opacity(0.85))
        .padding(.vertical, 2)
    }
}

// MARK: - Hooks Section — numbered, no fills

extension IdeaFocusModeView {
    private var atelierHooksSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            AtelierOrnamentalSectionLabel(label: "HOOKS")

            VStack(alignment: .leading, spacing: DS.space10) {
                ForEach(Array(viewModel.editableHooks.enumerated()), id: \.offset) { index, hook in
                    atelierHookRow(hook, at: index)
                }
                atelierAddHookRow
            }
            .padding(.horizontal, DS.space4)
        }
    }

    private func atelierHookRow(_ hook: String, at index: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
            Text(romanNumeral(for: index + 1) + ".")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.giltMuted)
                .frame(width: 28, alignment: .leading)

            Text(hook)
                .font(DS.callout)
                .foregroundStyle(DS.text)

            Spacer(minLength: DS.space8)

            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.editableHooks.remove(at: index)
                    viewModel.scheduleAutoSave()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.inkFaded.opacity(0.5))
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove hook")
        }
    }

    private var atelierAddHookRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space12) {
            Text("+")
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(DS.gilt.opacity(0.6))
                .frame(width: 28, alignment: .leading)

            TextField("add another", text: $newHookText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .italic()
                .foregroundStyle(DS.inkFaded)
                .onSubmit { addHook() }
                .accessibilityLabel("New hook text")
        }
        .padding(.top, DS.space4)
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
            viewModel.scheduleAutoSave()
        }
    }
}

// MARK: - Inline Outline Section

extension IdeaFocusModeView {
    @ViewBuilder
    private var atelierOutlineSection: some View {
        VStack(alignment: .leading, spacing: DS.space16) {
            atelierOutlineHeader

            if let outline = viewModel.codexOutline {
                if outlineAdvancedMode {
                    advancedOutlineWorkspace(outline)
                } else {
                    normalOutlineSlides(outline)
                }
            }
        }
        .onAppear {
            if viewModel.codexOutline == nil {
                viewModel.codexOutline = CodexOutlineModel(arcShape: nil, slides: [
                    CodexOutlineSlide(id: UUID(), position: 1, speechAct: nil,
                        readerDeltas: [], frame: nil, distance: nil,
                        techniques: [], transition: nil, note: nil)
                ])
            }
        }
    }

    private var atelierOutlineHeader: some View {
        HStack(spacing: DS.space12) {
            AtelierOrnamentalSectionLabel(label: "OUTLINE")
                .layoutPriority(0)

            HStack(spacing: DS.space12) {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        outlineAdvancedMode.toggle()
                    }
                } label: {
                    Text(outlineAdvancedMode ? "advanced" : "simple")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(outlineAdvancedMode ? DS.text : DS.inkFaded)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { addNewSlide() } label: {
                    Text("+ slide")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.gilt.opacity(0.8))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add slide")
            }
            .layoutPriority(1)
        }
    }

    // MARK: Normal Mode — floating stanzas, no cards

    private func normalOutlineSlides(_ outline: CodexOutlineModel) -> some View {
        VStack(alignment: .leading, spacing: DS.space20) {
            ForEach(outline.slides) { slide in
                normalSlideCard(slide)
            }
        }
        .padding(.horizontal, DS.space4)
    }

    private func normalSlideCard(_ slide: CodexOutlineSlide) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DS.space16) {
            Text(romanNumeral(for: slide.position))
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.giltMuted)
                .frame(width: 36, alignment: .leading)

            TextField("what should this slide do?",
                      text: slideNoteBinding(for: slide.id),
                      axis: .vertical)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(1...4)

            Button { removeSlide(slide.id) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(DS.inkFaded.opacity(0.4))
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
                if let idx = viewModel.codexOutline?.slides.firstIndex(where: { $0.id == slideId }) {
                    viewModel.codexOutline?.slides[idx].note = newValue
                }
            }
        )
    }

    // MARK: Legacy — kept for reference but no longer used
    @available(*, deprecated, message: "Replaced by outlineSection dual mode")
    private var _outlineStartButton: some View {
        Button {
            startOutlineWithArc(nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .accessibilityHidden(true)
                Text("Start Outline")
            }
            .font(DS.caption)
            .foregroundStyle(ideaAccent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(ideaAccent.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start outline")
    }

    // MARK: Inline Slides

    private func inlineOutlineSlides(_ outline: CodexOutlineModel) -> some View {
        VStack(spacing: DS.space8) {
            if let arc = outline.arcShape {
                inlineArcBadge(arc)
            }

            ForEach(outline.slides) { slide in
                inlineSlideCard(slide)
            }
        }
    }

    private func inlineArcBadge(_ arc: String) -> some View {
        HStack(spacing: 6) {
            Text("Arc:")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            CodexConceptTag(name: arc, color: CodexElementCategory.arcShape.color)
        }
    }

    private func inlineSlideCard(_ slide: CodexOutlineSlide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            inlineSlideCardHeader(slide)
            inlineSlideCardTags(slide)
            inlineSlideCardNote(slide)
        }
        .padding(8)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    private func inlineSlideCardHeader(_ slide: CodexOutlineSlide) -> some View {
        HStack {
            Text("Slide \(slide.position)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.accent, in: Capsule())
            Spacer()
            Button {
                removeSlide(slide.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove slide \(slide.position)")
        }
    }

    @ViewBuilder
    private func inlineSlideCardTags(_ slide: CodexOutlineSlide) -> some View {
        FlowLayout(spacing: 3) {
            if let sa = slide.speechAct {
                tagPill(sa, category: .speechAct)
            } else {
                emptySlot("Speech Act", hint: "The primary action this slide performs", category: .speechAct, slideId: slide.id, field: "speechAct")
            }

            ForEach(slide.readerDeltas, id: \.self) { delta in
                tagPill(delta, category: .readerDelta)
            }
            emptySlot("+", hint: "What the reader feels after this slide", category: .readerDelta, slideId: slide.id, field: "readerDelta")

            if let frame = slide.frame {
                tagPill(frame, category: .frame)
            }

            ForEach(slide.techniques, id: \.self) { tech in
                tagPill(tech, category: .technique)
            }
        }
    }

    @ViewBuilder
    private func inlineSlideCardNote(_ slide: CodexOutlineSlide) -> some View {
        if let note = slide.note, !note.isEmpty {
            Text(note)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .italic()
        }
    }

    // MARK: Tag Helpers

    private func tagPill(_ name: String, category: CodexElementCategory) -> some View {
        CodexConceptTag(name: name, color: category.color)
            .help("\(category.displayName): \(name)")
    }

    private func emptySlot(_ label: String, hint: String, category: CodexElementCategory, slideId: UUID, field: String) -> some View {
        Text(label)
            .font(.system(size: 9))
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(DS.borderSubtle)
            )
            .help(hint)
            .dropDestination(for: CodexDragItem.self) { items, _ in
                guard let item = items.first, item.category == category else { return false }
                addElementToSlide(slideId: slideId, field: field, name: item.canonicalName)
                return true
            }
    }

    // MARK: Outline Mutations

    private func startOutlineWithArc(_ arcName: String?) {
        let slideCount = viewModel.selectedContentType == "reel" ? 5 : 10
        let slides = (1...slideCount).map { i in
            CodexOutlineSlide(
                id: UUID(), position: i,
                speechAct: nil, readerDeltas: [], frame: nil,
                distance: nil, techniques: [], transition: nil, note: nil
            )
        }
        viewModel.codexOutline = CodexOutlineModel(arcShape: arcName, slides: slides)
        if let arcName { viewModel.selectedArcType = arcName }
    }

    private func addNewSlide() {
        guard var outline = viewModel.codexOutline else { return }
        let nextPos = (outline.slides.map(\.position).max() ?? 0) + 1
        outline.slides.append(CodexOutlineSlide(
            id: UUID(), position: nextPos,
            speechAct: nil, readerDeltas: [], frame: nil,
            distance: nil, techniques: [], transition: nil, note: nil
        ))
        viewModel.codexOutline = outline
    }

    private func removeSlide(_ id: UUID) {
        guard var outline = viewModel.codexOutline else { return }
        outline.slides.removeAll { $0.id == id }
        for i in outline.slides.indices {
            outline.slides[i].position = i + 1
        }
        viewModel.codexOutline = outline
    }

    private func addElementToSlide(slideId: UUID, field: String, name: String) {
        guard var outline = viewModel.codexOutline,
              let idx = outline.slides.firstIndex(where: { $0.id == slideId }) else { return }
        switch field {
        case "speechAct": outline.slides[idx].speechAct = name
        case "readerDelta": outline.slides[idx].readerDeltas.append(name)
        case "frame": outline.slides[idx].frame = name
        case "distance": outline.slides[idx].distance = name
        case "technique": outline.slides[idx].techniques.append(name)
        case "transition": outline.slides[idx].transition = name
        default: break
        }
        viewModel.codexOutline = outline
    }

    private func removeElementFromSlide(slideId: UUID, field: String, name: String) {
        guard var outline = viewModel.codexOutline,
              let idx = outline.slides.firstIndex(where: { $0.id == slideId }) else { return }
        switch field {
        case "speechAct": outline.slides[idx].speechAct = nil
        case "frame": outline.slides[idx].frame = nil
        case "distance": outline.slides[idx].distance = nil
        case "transition": outline.slides[idx].transition = nil
        case "readerDelta": outline.slides[idx].readerDeltas.removeAll { $0 == name }
        case "technique": outline.slides[idx].techniques.removeAll { $0 == name }
        default: break
        }
        viewModel.codexOutline = outline
    }
}

// MARK: - Advanced Outline Workspace

extension IdeaFocusModeView {

    /// Two-column advanced outline: slide editors (left) + element browser (right).
    private func advancedOutlineWorkspace(_ outline: CodexOutlineModel) -> some View {
        HStack(alignment: .top, spacing: DS.space12) {
            advancedSlideList(outline)
            AdvancedElementBrowser()
        }
    }

    private func advancedSlideList(_ outline: CodexOutlineModel) -> some View {
        ScrollView {
            VStack(spacing: DS.space8) {
                if let arc = outline.arcShape {
                    inlineArcBadge(arc)
                }
                ForEach(outline.slides) { slide in
                    advancedSlideCard(slide)
                }
            }
            .padding(.vertical, DS.space4)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: Advanced Slide Card

    private func advancedSlideCard(_ slide: CodexOutlineSlide) -> some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            advancedSlideHeader(slide)
            advancedSlidePhysicsGrid(slide)
        }
        .padding(DS.space10)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    private func advancedSlideHeader(_ slide: CodexOutlineSlide) -> some View {
        HStack(spacing: DS.space6) {
            slideBadge(slide.position)
            TextField("Note...", text: slideNoteBinding(for: slide.id), axis: .vertical)
                .font(DS.caption2)
                .foregroundStyle(DS.text)
                .textFieldStyle(.plain)
                .lineLimit(1...2)
            Spacer()
            slideDeleteButton(slide)
        }
    }

    private func slideBadge(_ position: Int) -> some View {
        Text("\(position)")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(DS.textOnAccent)
            .frame(width: 22, height: 22)
            .background(DS.entityIdea, in: Capsule())
    }

    private func slideDeleteButton(_ slide: CodexOutlineSlide) -> some View {
        Button { removeSlide(slide.id) } label: {
            Image(systemName: "trash")
                .font(.system(size: 10))
                .foregroundStyle(DS.textMuted)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Delete slide \(slide.position)")
    }

    // MARK: Physics Grid

    private func advancedSlidePhysicsGrid(_ slide: CodexOutlineSlide) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: DS.space6),
            GridItem(.flexible(), spacing: DS.space6)
        ]
        return LazyVGrid(columns: columns, alignment: .leading, spacing: DS.space6) {
            physicsSlot(
                "Speech Act", value: slide.speechAct,
                category: .speechAct, slideId: slide.id, field: "speechAct",
                hint: "The primary action this slide performs \u{2014} e.g., HOOK, CONFESSION, PROOF, REVEAL"
            )
            physicsSlot(
                "Frame", value: slide.frame,
                category: .frame, slideId: slide.id, field: "frame",
                hint: "How this slide is positioned \u{2014} e.g., SETUP, LOSS, TRANSFORMATION, TUTORIAL"
            )
            physicsMultiSlot(
                "Reader Deltas", values: slide.readerDeltas,
                category: .readerDelta, slideId: slide.id, field: "readerDelta",
                hint: "What the reader should feel after this slide \u{2014} e.g., CURIOSITY+, TRUST+, TENSION+"
            )
            physicsSlot(
                "Distance", value: slide.distance,
                category: .distance, slideId: slide.id, field: "distance",
                hint: "Reader\u{2019}s proximity \u{2014} ZERO (live scene), NEAR (remembered), FAR (observed)"
            )
            physicsMultiSlot(
                "Techniques", values: slide.techniques,
                category: .technique, slideId: slide.id, field: "technique",
                hint: "Craft moves active on this slide \u{2014} e.g., ELLIPSIS MOMENTUM, DIRECT DIALOGUE"
            )
            physicsSlot(
                "\u{2192} Next", value: slide.transition,
                category: .transition, slideId: slide.id, field: "transition",
                hint: "How this slide connects to the next \u{2014} e.g., ESCALATION, ANSWER, PIVOT"
            )
        }
    }

    // MARK: Single-Value Physics Slot

    private func physicsSlot(
        _ label: String,
        value: String?,
        category: CodexElementCategory,
        slideId: UUID,
        field: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            slotLabel(label)
            if let val = value {
                filledSingleSlot(val, category: category, slideId: slideId, field: field)
            } else {
                emptySingleSlot(label, category: category, slideId: slideId, field: field)
            }
        }
        .help(hint)
    }

    private func filledSingleSlot(
        _ val: String,
        category: CodexElementCategory,
        slideId: UUID,
        field: String
    ) -> some View {
        HStack(spacing: 2) {
            CodexConceptTag(name: val, color: category.color)
            slotRemoveButton {
                removeElementFromSlide(slideId: slideId, field: field, name: val)
            }
        }
    }

    private func emptySingleSlot(
        _ label: String,
        category: CodexElementCategory,
        slideId: UUID,
        field: String
    ) -> some View {
        Text(label)
            .font(.system(size: 8))
            .foregroundStyle(DS.textMuted.opacity(0.5))
            .frame(maxWidth: .infinity, minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(DS.borderSubtle)
            )
            .contentShape(Rectangle())
            .dropDestination(for: CodexDragItem.self) { items, _ in
                guard let item = items.first, item.category == category else { return false }
                addElementToSlide(slideId: slideId, field: field, name: item.canonicalName)
                return true
            } isTargeted: { targeted in
                // Visual feedback when dragging over
            }
    }

    // MARK: Multi-Value Physics Slot

    private func physicsMultiSlot(
        _ label: String,
        values: [String],
        category: CodexElementCategory,
        slideId: UUID,
        field: String,
        hint: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            slotLabel(label)
            multiSlotContent(values, category: category, slideId: slideId, field: field)
        }
        .help(hint)
    }

    private func multiSlotContent(
        _ values: [String],
        category: CodexElementCategory,
        slideId: UUID,
        field: String
    ) -> some View {
        FlowLayout(spacing: 2) {
            ForEach(values, id: \.self) { val in
                HStack(spacing: 1) {
                    CodexConceptTag(name: val, color: category.color)
                    slotRemoveButton {
                        removeElementFromSlide(slideId: slideId, field: field, name: val)
                    }
                }
            }
            multiSlotDropTarget(category: category, slideId: slideId, field: field)
        }
    }

    private func multiSlotDropTarget(
        category: CodexElementCategory,
        slideId: UUID,
        field: String
    ) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .foregroundStyle(DS.borderSubtle)
            .frame(width: 20, height: 18)
            .overlay(
                Image(systemName: "plus")
                    .font(.system(size: 7))
                    .foregroundStyle(DS.textMuted.opacity(0.5))
                    .accessibilityHidden(true)
            )
            .dropDestination(for: CodexDragItem.self) { items, _ in
                guard let item = items.first, item.category == category else { return false }
                addElementToSlide(slideId: slideId, field: field, name: item.canonicalName)
                return true
            }
    }

    // MARK: Slot Shared Helpers

    private func slotLabel(_ text: String) -> some View {
        Text(text)
            .dsSmallCapsLabel()
    }

    private func slotRemoveButton(action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(ProMotionSprings.snappy) { action() }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove element")
    }
}

// MARK: - Marginalia Gutter (the intelligence, rendered as marginal notes)

extension IdeaFocusModeView {
    /// 260pt right gutter. Transparent, no dividers, no card chrome — just smallCaps
    /// section labels and quiet rows. Each section reveals its full panel as a modal
    /// sheet rather than dominating the gutter inline.
    private var marginaliaGutter: some View {
        VStack(alignment: .leading, spacing: DS.space24) {
            marginaliaSwipesSection
                .atelierStaggerIn(delay: 0.56, appeared: hasAppeared)
            marginaliaFrameworkSection
                .atelierStaggerIn(delay: 0.60, appeared: hasAppeared)
            marginaliaBlueprintSection
                .atelierStaggerIn(delay: 0.64, appeared: hasAppeared)
            marginaliaResearchSection
                .atelierStaggerIn(delay: 0.68, appeared: hasAppeared)
            marginaliaCosmoSection
                .atelierStaggerIn(delay: 0.72, appeared: hasAppeared)
        }
    }

    // MARK: Swipes — vertical list, up to 3 visible

    private var marginaliaSwipesSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("SWIPES",
                            countText: viewModel.linkedSwipes.isEmpty
                                ? nil
                                : "\(viewModel.linkedSwipes.count) matched")

            if viewModel.linkedSwipes.isEmpty {
                Button {
                    viewModel.showLinkSwipesOverlay = true
                } label: {
                    Text("add swipes →")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.inkFaded.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Link swipes")
            } else {
                VStack(alignment: .leading, spacing: DS.space8) {
                    ForEach(viewModel.linkedSwipes.prefix(3), id: \.uuid) { swipe in
                        marginaliaSwipeRow(swipe)
                    }
                    HStack(spacing: DS.space8) {
                        Button {
                            viewModel.showLinkSwipesOverlay = true
                        } label: {
                            Text("add / remove →")
                                .font(DS.dateSerif)
                                .italic()
                                .foregroundStyle(DS.gilt.opacity(0.7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)

                        if viewModel.linkedSwipes.count > 3 {
                            Button {
                                viewModel.showLinkSwipesOverlay = true
                            } label: {
                                Text("see all \(viewModel.linkedSwipes.count)")
                                    .font(DS.dateSerif)
                                    .italic()
                                    .foregroundStyle(DS.inkFaded)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, DS.space2)
                }
            }
        }
    }

    private func marginaliaSwipeRow(_ swipe: Atom) -> some View {
        HStack(alignment: .top, spacing: DS.space8) {
            Button {
                openAtomInPane(swipe.uuid)
            } label: {
                HStack(alignment: .top, spacing: DS.space8) {
                    Rectangle()
                        .fill(DS.entitySwipe.opacity(0.18))
                        .frame(width: 3)
                        .frame(maxHeight: .infinity)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(swipe.title ?? "Untitled")
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                            .lineLimit(2)
                        if let hook = swipe.researchMetadata?.hook {
                            Text(hook)
                                .font(DS.caption2)
                                .foregroundStyle(DS.inkFaded)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                Task { await viewModel.unlinkSwipe(swipe.uuid) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.inkFaded)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove swipe \(swipe.title ?? "untitled")")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Framework — name + confidence + change

    private var marginaliaFrameworkSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("FRAMEWORK")

            if let framework = viewModel.selectedArcType ?? viewModel.arcRecommendations.first?.arcName {
                VStack(alignment: .leading, spacing: DS.space4) {
                    Text(framework)
                        .font(.system(size: 14, weight: .regular, design: .serif))
                        .foregroundStyle(DS.text)

                    if let top = viewModel.arcRecommendations.first(where: { $0.arcName == framework }) {
                        Text("\(Int(top.confidence * 100)) % match")
                            .font(.system(size: 10, weight: .regular, design: .monospaced))
                            .foregroundStyle(DS.inkFaded)
                    }

                    Button {
                        showFrameworkSheet = true
                    } label: {
                        Text("change →")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.gilt.opacity(0.7))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DS.space2)
                }
            } else {
                Button {
                    refreshArcRecommendations()
                    showFrameworkSheet = true
                } label: {
                    Text(isLoadingArcRecs ? "analyzing…" : "suggest →")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.inkFaded.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isLoadingArcRecs)
            }
        }
    }

    private func refreshArcRecommendations() {
        isLoadingArcRecs = true
        viewModel.arcRecommendations = []
        Task {
            await viewModel.generateArcRecommendations()
            isLoadingArcRecs = false
        }
    }

    // MARK: Blueprint — one-line summary, expand opens sheet

    private var marginaliaBlueprintSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("BLUEPRINT")

            if let blueprint = viewModel.selectedBlueprint {
                VStack(alignment: .leading, spacing: DS.space4) {
                    Button {
                        showBlueprintSheet = true
                    } label: {
                        Text(blueprint.title?.lowercased() ?? "blueprint")
                            .font(.system(size: 14, weight: .regular, design: .serif))
                            .foregroundStyle(DS.text)
                            .lineLimit(2)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    HStack(spacing: DS.space8) {
                        Button {
                            showBlueprintSheet = true
                        } label: {
                            Text("expand →")
                                .font(DS.dateSerif)
                                .italic()
                                .foregroundStyle(DS.gilt.opacity(0.7))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            showBlueprintPicker = true
                        } label: {
                            Text("change")
                                .font(DS.dateSerif)
                                .italic()
                                .foregroundStyle(DS.inkFaded)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            viewModel.clearBlueprint()
                        } label: {
                            Text("remove")
                                .font(DS.dateSerif)
                                .italic()
                                .foregroundStyle(DS.inkFaded)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, DS.space2)
                }
            } else {
                Button {
                    showBlueprintPicker = true
                } label: {
                    Text("select blueprint →")
                        .font(DS.dateSerif)
                        .italic()
                        .foregroundStyle(DS.inkFaded.opacity(0.7))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func openAtomInPane(_ uuid: String) {
        NotificationCenter.default.post(
            name: CosmoNotification.Navigation.openBlockInFocusMode,
            object: nil,
            userInfo: ["atomUUID": uuid, "asPane": true]
        )
    }

    // MARK: Research — stat lines, tap opens sheet

    private var marginaliaResearchSection: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            MarginaliaLabel("RESEARCH")

            Button {
                showResearchSheet = true
            } label: {
                VStack(alignment: .leading, spacing: DS.space4) {
                    if viewModel.researchResults.isEmpty {
                        Text("no sources yet →")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.inkFaded.opacity(0.7))
                    } else {
                        Text("· \(viewModel.researchResults.count) sources")
                            .font(DS.callout)
                            .foregroundStyle(DS.text)
                        Text("open panel →")
                            .font(DS.dateSerif)
                            .italic()
                            .foregroundStyle(DS.gilt.opacity(0.7))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Cosmo — smart agent inline (Gemini 3 Flash, full tool access)

    private var marginaliaCosmoSection: some View {
        FocusCosmoPanel(session: cosmoSession, isExpanded: $chatExpanded)
            .task { await cosmoSession.load() }
    }

}

// MARK: - CTA — gilt-bracketed serif "begin writing"

extension IdeaFocusModeView {
    private var atelierCTA: some View {
        HStack {
            Spacer()
            GiltBracketedCTA(
                title: isPromoting ? "writing…" : "begin writing",
                disabled: isPromoting || isBodyEmpty,
                action: beginWriting
            )
            .keyboardShortcut(.return, modifiers: [.command])
            Spacer()
        }
    }

    private func beginWriting() {
        guard !isPromoting, !isBodyEmpty else { return }
        isPromoting = true
        Task {
            await viewModel.promoteToContent()
            isPromoting = false
        }
    }
}

// MARK: - Flow Layout

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            guard index < subviews.count else { break }
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }

            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }

        return (CGSize(width: maxWidth, height: totalHeight), positions)
    }
}

// MARK: - Preview

#if DEBUG
struct IdeaFocusModeView_Previews: PreviewProvider {
    static var previews: some View {
        IdeaFocusModeView(
            atom: Atom.new(
                type: .idea,
                title: "The Paradox of Productivity",
                body: "Most people optimize for output when they should be optimizing for clarity. The real bottleneck is not time -- it is attention quality."
            ),
            onClose: { print("Close") }
        )
        .frame(width: 1200, height: 800)
    }
}
#endif

// MARK: - Cosmo Context Provider

@MainActor
class IdeaContextProvider: CosmoContextProvider {
    private let atom: Atom
    private weak var viewModel: IdeaFocusModeViewModel?

    init(atom: Atom, viewModel: IdeaFocusModeViewModel) {
        self.atom = atom
        self.viewModel = viewModel
    }

    var contextType: CosmoContextType { .ideaFocusMode }

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
