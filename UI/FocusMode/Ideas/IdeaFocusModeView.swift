// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeView.swift
// 2-column brainstorm workspace: left editing, right intelligence panel, bottom action bar
// April 2026 — Full rewrite

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Idea Focus Mode View

/// Full-screen brainstorm workspace for ideas.
/// Left column: editable title, context/direction, hooks, supporting swipes.
/// Right column: fixed 320pt intelligence panel (blueprint, research, arcs, chat).
/// Bottom: action bar with content type toggle and write CTA.
struct IdeaFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: IdeaFocusModeViewModel
    @State private var newHookText: String = ""
    @State private var showProfileEditor: Bool = false
    @State private var showBlueprintPicker: Bool = false
    @State private var isLoadingArcRecs: Bool = false
    @State private var chatExpanded: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isContextFocused: Bool

    // MARK: - Constants

    private let ideaGold = DS.entityIdea

    @AppStorage("sidebarCollapsed") private var isSidebarHidden: Bool = false
    @Environment(\.isPaneContext) private var isPaneContext
    @Environment(\.isPaneActive) private var isPaneActive

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: IdeaFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                HStack(spacing: 0) {
                    leftColumn
                    intelligencePanel
                }

                actionBar
            }

            overlayPresentations
        }
        .onAppear {
            AtomRepository.shared.acquireEditingLock(uuid: atom.uuid)
            let provider = IdeaContextProvider(atom: atom, viewModel: viewModel)
            if !isPaneContext || isPaneActive {
                CosmoWindowViewModel.shared.updateContext(provider: provider)
            }
        }
        .onChange(of: isPaneActive) { _, isActive in
            if isActive {
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

// MARK: - Header Bar

extension IdeaFocusModeView {
    private var headerBar: some View {
        HStack(spacing: DS.space12) {
            headerLeadingGroup
            ideaBadge
            clientPickerPill
            Spacer()
            writeButton
            headerTrailingGroup
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(DS.bg)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.border).frame(height: 1)
        }
    }

    @ViewBuilder
    private var headerLeadingGroup: some View {
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
            .help(isSidebarHidden ? "Show sidebar" : "Hide sidebar")
            .accessibilityLabel("Toggle sidebar")

            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(DS.buttonText)
                    Text("Back")
                        .font(DS.callout)
                }
                .foregroundStyle(DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.surface, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Go back")
        }
    }

    private var ideaBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "lightbulb.fill")
                .foregroundStyle(ideaGold)
                .accessibilityHidden(true)
            Text("Idea")
                .foregroundStyle(ideaGold)
        }
        .font(DS.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(ideaGold.opacity(0.12), in: Capsule())
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
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle.fill")
                    .font(DS.caption)
                    .accessibilityHidden(true)
                Text(client.title ?? "Client")
                    .font(DS.caption)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(DS.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DS.surface, in: Capsule())
            .overlay(Capsule().stroke(DS.border, lineWidth: 0.5))
        } else {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                    .accessibilityHidden(true)
                Text("No client")
                    .font(DS.caption)
            }
            .foregroundStyle(DS.textMuted)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(DS.surface, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(
                        DS.textMuted.opacity(0.3),
                        style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                    )
            )
        }
    }

    private var writeButton: some View {
        Button {
            Task { await viewModel.promoteToContent() }
        } label: {
            writeButtonLabel
        }
        .buttonStyle(.plain)
        .disabled(isBodyEmpty)
        .opacity(isBodyEmpty ? 0.5 : 1)
        .accessibilityLabel("Write content from this idea")
    }

    @ViewBuilder
    private var writeButtonLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "pencil.line")
                .accessibilityHidden(true)
            Text("Write")
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(DS.textOnAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(DS.green, in: Capsule())
    }

    @ViewBuilder
    private var headerTrailingGroup: some View {
        if isPaneContext {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(DS.buttonText)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 28, height: 28)
                    .background(DS.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close pane")
        }
    }

    private var isBodyEmpty: Bool {
        viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

// MARK: - Left Column

extension IdeaFocusModeView {
    private var leftColumn: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space24) {
                if isBodyEmpty && !isContextFocused {
                    emptyStateView
                }

                titleEditor
                contextEditor
                hooksSection
                outlineSection
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity)
    }

    private var emptyStateView: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 36))
                .foregroundStyle(ideaGold.opacity(0.4))
                .accessibilityHidden(true)

            Text("What's this idea about?")
                .font(DS.title2)
                .foregroundStyle(DS.textSecondary)

            Text("Describe the angle, key points, and why it matters.\nThe more context you give, the better the AI can help.")
                .font(DS.callout)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private var titleEditor: some View {
        TextField("Idea title...", text: $viewModel.editableTitle)
            .textFieldStyle(.plain)
            .font(DS.pageTitle)
            .foregroundStyle(DS.text)
            .focused($isTitleFocused)
            .onChange(of: viewModel.editableTitle) { _ in
                viewModel.scheduleAutoSave()
            }
            .accessibilityLabel("Idea title")
    }

    private var contextEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            contextEditorHeader
            contextEditorBody
        }
    }

    private var contextEditorHeader: some View {
        HStack(spacing: 6) {
            Text("CONTEXT & DIRECTION")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)
            Spacer()
            wordCount
        }
    }

    private var contextEditorBody: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(ideaGold)
                .frame(width: 3)

            TextEditor(text: $viewModel.editableBody)
                .font(DS.body)
                .foregroundStyle(DS.text)
                .lineSpacing(5)
                .scrollContentBackground(.hidden)
                .focused($isContextFocused)
                .frame(minHeight: 240, maxHeight: 500)
                .padding(14)
                .onChange(of: viewModel.editableBody) { _ in
                    viewModel.scheduleAutoSave()
                    viewModel.autoEnrich()
                }
                .accessibilityLabel("Idea context and direction")
        }
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusMedium))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusMedium)
                .stroke(isContextFocused ? ideaGold.opacity(0.5) : DS.border, lineWidth: 1)
        )
    }

    private var wordCount: some View {
        Text("\(viewModel.editableBody.split(separator: " ").count) words")
            .font(DS.caption2)
            .foregroundStyle(DS.textMuted)
    }
}

// MARK: - Hooks Section

extension IdeaFocusModeView {
    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HOOKS")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)

            ForEach(Array(viewModel.editableHooks.enumerated()), id: \.offset) { index, hook in
                hookRow(hook, at: index)
            }

            addHookField
        }
    }

    private func hookRow(_ hook: String, at index: Int) -> some View {
        HStack(spacing: 8) {
            Text(hook)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineLimit(2)
            Spacer()
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.editableHooks.remove(at: index)
                    viewModel.scheduleAutoSave()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove hook")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ideaGold.opacity(0.06), in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(ideaGold.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var addHookField: some View {
        HStack(spacing: 6) {
            Image(systemName: "plus.circle.fill")
                .font(DS.callout)
                .foregroundStyle(ideaGold.opacity(0.5))
                .accessibilityHidden(true)
            TextField("Add a hook...", text: $newHookText)
                .textFieldStyle(.plain)
                .font(DS.callout)
                .onSubmit { addHook() }
                .accessibilityLabel("New hook text")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(DS.surface, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.borderSubtle, lineWidth: 1)
        )
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
    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            outlineSectionHeader

            if let outline = viewModel.codexOutline, !outline.slides.isEmpty {
                inlineOutlineSlides(outline)
            } else {
                outlineEmptyState
            }
        }
    }

    private var outlineSectionHeader: some View {
        HStack {
            Text("OUTLINE")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)

            if let outline = viewModel.codexOutline, !outline.slides.isEmpty {
                outlineSlideCountBadge(outline.slides.count)
            }

            Spacer()

            if viewModel.codexOutline != nil {
                Button {
                    addNewSlide()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "plus")
                            .accessibilityHidden(true)
                        Text("Slide")
                    }
                    .font(DS.caption)
                    .foregroundStyle(ideaGold)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add slide")
            }
        }
    }

    private func outlineSlideCountBadge(_ count: Int) -> some View {
        Text("\(count) slides")
            .font(DS.caption2)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DS.accent.opacity(0.12), in: Capsule())
    }

    // MARK: Empty State

    private var outlineEmptyState: some View {
        VStack(spacing: DS.space8) {
            Text("Plan your post's physics before writing")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            if !viewModel.arcRecommendations.isEmpty {
                outlineArcPicker
            } else {
                outlineStartButton
            }
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated.opacity(0.3), in: .rect(cornerRadius: DS.radiusMedium))
    }

    private var outlineArcPicker: some View {
        VStack(spacing: 4) {
            ForEach(viewModel.arcRecommendations.prefix(3)) { rec in
                outlineArcPickerRow(rec)
            }
        }
    }

    private func outlineArcPickerRow(_ rec: ArcRecommendation) -> some View {
        Button {
            startOutlineWithArc(rec.arcName)
        } label: {
            HStack {
                CodexConceptTag(name: rec.arcName, color: CodexElementCategory.arcShape.color)
                Text(rec.explanation)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textSecondary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .accessibilityHidden(true)
            }
            .padding(8)
            .background(DS.surface, in: .rect(cornerRadius: DS.radiusSmall))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Start outline with \(rec.arcName) arc")
    }

    private var outlineStartButton: some View {
        Button {
            startOutlineWithArc(nil)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "list.bullet.rectangle")
                    .accessibilityHidden(true)
                Text("Start Outline")
            }
            .font(DS.caption)
            .foregroundStyle(ideaGold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(ideaGold.opacity(0.1), in: Capsule())
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
}

// MARK: - Supporting Swipes Section

extension IdeaFocusModeView {
    private var supportingSwipesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            supportingSwipesHeader
            supportingSwipesContent
        }
    }

    private var supportingSwipesHeader: some View {
        HStack {
            Text("SUPPORTING SWIPES")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)
            Spacer()
            Button {
                viewModel.showLinkSwipesOverlay = true
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .accessibilityHidden(true)
                    Text("Link")
                }
                .font(DS.caption)
                .foregroundStyle(ideaGold)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Link a swipe file")
        }
    }

    @ViewBuilder
    private var supportingSwipesContent: some View {
        if viewModel.linkedSwipes.isEmpty {
            Text("Link swipes to give the AI structural inspiration")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .italic()
                .padding(.vertical, 8)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.linkedSwipes, id: \.uuid) { swipe in
                        compactSwipeCard(swipe)
                    }
                }
            }
        }
    }

    private func compactSwipeCard(_ swipe: Atom) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(swipe.title ?? "Untitled")
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.text)
                .lineLimit(2)
            if let hook = swipe.researchMetadata?.hook {
                Text(hook)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
        .frame(width: 160)
        .padding(10)
        .background(DS.surface, in: .rect(cornerRadius: DS.radiusSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(DS.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Intelligence Panel (Right Column)

extension IdeaFocusModeView {
    private var intelligencePanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space20) {
                blueprintSection
                supportingSwipesSection
                researchSection
                arcRecommendationsSection
                chatSection
            }
            .padding(DS.space16)
        }
        .scrollIndicators(.hidden)
        .frame(width: 320)
        .background(DS.surface)
        .overlay(alignment: .leading) {
            Rectangle().fill(DS.border).frame(width: 1)
        }
    }

    // MARK: Blueprint

    private var blueprintSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BLUEPRINT")
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)

            if let blueprint = viewModel.selectedBlueprint {
                BlueprintDisplayView(
                    blueprintAtom: blueprint,
                    displayMode: $viewModel.blueprintDisplayMode
                )
            } else {
                blueprintEmptyState
            }
        }
    }

    private var blueprintEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(DS.textMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text("Choose a proven post as your structural skeleton")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
            Button {
                showBlueprintPicker = true
            } label: {
                blueprintSelectLabel
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Select blueprint")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space16)
        .background(DS.surfaceElevated.opacity(0.5), in: .rect(cornerRadius: DS.radiusMedium))
    }

    @ViewBuilder
    private var blueprintSelectLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "plus.circle.fill")
                .accessibilityHidden(true)
            Text("Select Blueprint")
        }
        .font(DS.caption)
        .foregroundStyle(ideaGold)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ideaGold.opacity(0.1), in: Capsule())
    }

    // MARK: Research

    private var researchSection: some View {
        IdeaResearchPanel(
            results: $viewModel.researchResults,
            ideaText: viewModel.editableBody,
            clientNiche: viewModel.linkedClient?.title
        )
    }

    // MARK: Arc Recommendations

    private var arcRecommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ARC RECOMMENDATIONS")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Button {
                    refreshArcRecommendations()
                } label: {
                    if isLoadingArcRecs {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.accent)
                    }
                }
                .buttonStyle(.plain)
                .disabled(isLoadingArcRecs || viewModel.editableBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel("Refresh arc recommendations")
            }

            if isLoadingArcRecs {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Analyzing idea...")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                }
                .padding(.vertical, 8)
            } else if viewModel.arcRecommendations.isEmpty {
                Text("Add context to get arc suggestions")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
                    .italic()
            } else {
                ForEach(viewModel.arcRecommendations) { rec in
                    arcRecommendationCard(rec)
                }
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

    private func arcRecommendationCard(_ rec: ArcRecommendation) -> some View {
        Button {
            viewModel.selectedArcType = rec.arcName
        } label: {
            arcRecommendationCardContent(rec)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func arcRecommendationCardContent(_ rec: ArcRecommendation) -> some View {
        let isSelected = viewModel.selectedArcType == rec.arcName

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                CodexConceptTag(name: rec.arcName, color: CodexElementCategory.arcShape.color)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DS.green)
                        .font(DS.caption)
                        .accessibilityLabel("Selected")
                }
            }
            Text(rec.explanation)
                .font(DS.caption2)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(
            isSelected ? DS.green.opacity(0.06) : DS.surfaceElevated,
            in: .rect(cornerRadius: DS.radiusSmall)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .stroke(
                    isSelected ? DS.green.opacity(0.3) : DS.borderSubtle,
                    lineWidth: 0.5
                )
        )
    }

    // MARK: Chat

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            chatToggleHeader
            chatContent
        }
    }

    private var chatToggleHeader: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                chatExpanded.toggle()
            }
        } label: {
            HStack {
                Text("BRAINSTORM CHAT")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(DS.textMuted)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DS.textMuted)
                    .rotationEffect(.degrees(chatExpanded ? 90 : 0))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(chatExpanded ? "Collapse brainstorm chat" : "Expand brainstorm chat")
    }

    @ViewBuilder
    private var chatContent: some View {
        if chatExpanded {
            IdeaChatPanel(
                messages: $viewModel.chatHistory,
                ideaContext: viewModel.editableBody
            )
            .frame(height: 300)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }
}

// MARK: - Action Bar

extension IdeaFocusModeView {
    private var actionBar: some View {
        HStack(spacing: 16) {
            contentTypePicker
            Spacer()
            actionBarWriteButton
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(DS.surface)
        .overlay(alignment: .top) {
            Rectangle().fill(DS.border).frame(height: 1)
        }
    }

    private var contentTypePicker: some View {
        Picker("Type", selection: Binding(
            get: { viewModel.selectedContentType ?? "carousel" },
            set: { viewModel.selectedContentType = $0 }
        )) {
            Text("Reel").tag("reel")
            Text("Carousel").tag("carousel")
        }
        .pickerStyle(.segmented)
        .frame(width: 180)
        .accessibilityLabel("Content type")
    }

    private var actionBarWriteButton: some View {
        Button {
            Task { await viewModel.promoteToContent() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "pencil.line")
                    .accessibilityHidden(true)
                Text("Write")
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.textOnAccent)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(DS.green, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isBodyEmpty)
        .opacity(isBodyEmpty ? 0.5 : 1)
        .accessibilityLabel("Write content from this idea")
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

    var availableActions: [CosmoWindowAction] { [] }
}
