// CosmoOS/UI/FocusMode/Content/ContentDraftView.swift
// Step 2 of Content Focus Mode - Sidebar outline + rich text editor
// February 2026 — Enhanced with inline AI action bar on text selection

import SwiftUI
import AppKit
import Combine

// MARK: - Selection Info

/// Describes the current text selection in the draft editor, including
/// the selected string, its NSRange, and a screen-relative rect for positioning overlays.
struct DraftSelectionInfo: Equatable {
    let text: String
    let range: NSRange
    let rectInEditor: CGRect

    static let empty = DraftSelectionInfo(text: "", range: NSRange(location: 0, length: 0), rectInEditor: .zero)
}

// MARK: - Inline AI State

/// Tracks the inline AI action bar lifecycle.
enum InlineAIState: Equatable {
    case idle
    case showingBar
    case processing(AIWritingAction)
    case showingResult
}

// MARK: - Content Draft View

struct ContentDraftView: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    let onBack: () -> Void
    let onNext: () -> Void

    @State private var isSidebarVisible = true
    @State private var autoSaveTask: Task<Void, Never>?
    @State private var saveState: DraftSaveState = .idle
    @State private var contentAppeared = false
    @State private var showAIAssistant = false
    @State private var selectedText = ""

    // AI Draft generation state
    @State private var isGeneratingDraft = false
    @State private var draftGenerationError: String?

    // Inline AI state
    @State private var selectionInfo: DraftSelectionInfo = .empty
    @State private var inlineAIState: InlineAIState = .idle
    @State private var showCustomPrompt = false
    @State private var customPromptText = ""
    @StateObject private var inlineAssistant = AIWritingAssistant()

    // Geometry for positioning
    @State private var editorAreaFrame: CGRect = .zero

    private let autoSaveDelay: TimeInterval = 1.5
    private let editorWidth: CGFloat = CosmoTypography.optimalReadingWidth
    private let sidebarWidth: CGFloat = 240

    enum DraftSaveState {
        case idle
        case saving
        case saved
    }

    var body: some View {
        VStack(spacing: 0) {
            // Main layout
            HStack(spacing: 0) {
                // MARK: - Collapsible Sidebar
                if isSidebarVisible {
                    sidebar
                        .frame(width: sidebarWidth)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                }

                // Divider
                if isSidebarVisible {
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 1)
                }

                // MARK: - Editor Area
                editorArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxHeight: .infinity)

            // MARK: - Bottom Bar
            bottomBar
        }
        .background(CosmoColors.thinkspaceVoid)
        .onAppear {
            withAnimation(ProMotionSprings.cardEntrance) {
                contentAppeared = true
            }
        }
        .onDisappear {
            autoSaveTask?.cancel()
        }
        // Keyboard shortcuts for inline AI
        .background(inlineAIKeyboardShortcuts)
    }

    // MARK: - Keyboard Shortcuts

    @ViewBuilder
    private var inlineAIKeyboardShortcuts: some View {
        Group {
            // Cmd+Shift+E — Expand
            Button(action: { triggerInlineAction(.expand) }) { EmptyView() }
                .keyboardShortcut("e", modifiers: [.command, .shift])

            // Cmd+Shift+C — Condense
            Button(action: { triggerInlineAction(.condense) }) { EmptyView() }
                .keyboardShortcut("c", modifiers: [.command, .shift])

            // Cmd+Shift+R — Rephrase
            Button(action: { triggerInlineAction(.rephrase) }) { EmptyView() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            // Cmd+Shift+Return — Continue Writing
            Button(action: { triggerInlineAction(.continueWriting) }) { EmptyView() }
                .keyboardShortcut(.return, modifiers: [.command, .shift])

            // Cmd+J — Full AI Assistant overlay
            Button(action: {
                let draft = state.draftContent
                if draft.isEmpty {
                    selectedText = ""
                } else {
                    let paragraphs = draft.components(separatedBy: "\n\n").filter { !$0.isEmpty }
                    selectedText = paragraphs.last ?? String(draft.suffix(500))
                }
                showAIAssistant.toggle()
            }) { EmptyView() }
                .keyboardShortcut("j", modifiers: .command)
        }
        .frame(width: 0, height: 0)
        .opacity(0)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Sidebar header
            HStack {
                Text("Outline")
                    .font(CosmoTypography.label)
                    .foregroundColor(.white.opacity(0.6))
                Spacer()
                Button(action: {
                    withAnimation(ProMotionSprings.snappy) {
                        isSidebarVisible = false
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.4))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Outline checklist
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(state.sortedOutline) { item in
                        outlineChecklistRow(item)
                    }

                    if state.outline.isEmpty {
                        VStack(spacing: 6) {
                            Image(systemName: "list.bullet")
                                .font(.system(size: 18))
                                .foregroundColor(.white.opacity(0.15))
                            Text("No outline items")
                                .font(CosmoTypography.caption)
                                .foregroundColor(.white.opacity(0.25))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(height: 1)

            // Related atoms section
            VStack(alignment: .leading, spacing: 8) {
                Text("Related")
                    .font(CosmoTypography.caption)
                    .foregroundColor(.white.opacity(0.4))

                if state.relatedAtoms.isEmpty {
                    Text("None found")
                        .font(CosmoTypography.caption)
                        .foregroundColor(.white.opacity(0.2))
                } else {
                    ForEach(state.relatedAtoms.prefix(5)) { ref in
                        HStack(spacing: 6) {
                            Image(systemName: ref.type.iconName)
                                .font(.system(size: 10))
                                .foregroundColor(relatedTypeColor(ref.type))
                            Text(ref.title)
                                .font(CosmoTypography.caption)
                                .foregroundColor(.white.opacity(0.5))
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(CosmoColors.thinkspaceSecondary.opacity(0.5))
    }

    // MARK: - Outline Checklist Row

    private func outlineChecklistRow(_ item: OutlineItem) -> some View {
        Button(action: {
            withAnimation(ProMotionSprings.snappy) {
                state.toggleOutlineItem(id: item.id)
                state.save()
            }
        }) {
            HStack(spacing: 8) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundColor(
                        item.isCompleted ? CosmoColors.blockContent : .white.opacity(0.3)
                    )

                Text(item.title)
                    .font(CosmoTypography.bodySmall)
                    .foregroundColor(
                        item.isCompleted ? .white.opacity(0.35) : .white.opacity(0.7)
                    )
                    .strikethrough(item.isCompleted, color: .white.opacity(0.2))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Editor Area

    private var editorArea: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Sidebar toggle when hidden
                if !isSidebarVisible {
                    sidebarToggleButton
                }

                // Centered editor with NSTextView
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Title (read-only, from atom)
                        Text(atom.title ?? "Untitled Content")
                            .font(CosmoTypography.display)
                            .foregroundColor(.white)
                            .padding(.bottom, 8)

                        // Core idea subtitle
                        if !state.coreIdea.isEmpty {
                            Text(state.coreIdea)
                                .font(CosmoTypography.body)
                                .foregroundColor(.white.opacity(0.4))
                                .padding(.bottom, 20)
                        }

                        Rectangle()
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 1)
                            .padding(.bottom, 24)

                        // AI Draft button — visible when draft is empty
                        if state.draftContent.isEmpty {
                            aiDraftButton
                        }

                        // Draft editor — NSTextView for selection tracking
                        DraftEditorTextView(
                            text: $state.draftContent,
                            onSelectionChanged: { info in
                                handleSelectionChange(info)
                            },
                            onTextChanged: {
                                triggerAutoSave()
                            }
                        )
                        .frame(minHeight: 400)
                    }
                    .frame(width: editorWidth)
                    .padding(.vertical, 40)
                }
                .frame(maxWidth: .infinity)
                .opacity(contentAppeared ? 1 : 0)
                .offset(y: contentAppeared ? 0 : 16)

                // Inline AI Action Bar — floats above selection
                if inlineAIState == .showingBar && !selectionInfo.text.isEmpty {
                    inlineActionBar
                        .position(
                            x: min(max(selectionInfo.rectInEditor.midX, 120), geo.size.width - 120),
                            y: max(selectionInfo.rectInEditor.minY - 50, 20)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottom)))
                }

                // Inline AI Result Popover
                if inlineAIState == .processing(.expand) || inlineAIState == .processing(.condense) ||
                   inlineAIState == .processing(.rephrase) || inlineAIState == .processing(.continueWriting) ||
                   inlineAIState == .showingResult {
                    inlineResultPopover
                        .position(
                            x: min(max(selectionInfo.rectInEditor.midX, 180), geo.size.width - 180),
                            y: max(selectionInfo.rectInEditor.minY - 80, 60)
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .bottom)))
                }

                // Floating AI sparkle button (bottom-right)
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        sparkleButton
                    }
                }

                // AI Assistant Overlay (Cmd+J full panel)
                if showAIAssistant {
                    AIAssistantOverlay(
                        selectedText: $selectedText,
                        isVisible: $showAIAssistant,
                        onApply: { newText in
                            state.draftContent = newText
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .onAppear {
                editorAreaFrame = geo.frame(in: .global)
            }
            .onChange(of: geo.size) { _, _ in
                editorAreaFrame = geo.frame(in: .global)
            }
        }
    }

    // MARK: - AI Draft Button

    @ViewBuilder
    private var aiDraftButton: some View {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        let hasDraftReady = metadata?.draftReady == true
        let swipeCount = metadata?.inheritedSwipeUUIDs?.count ?? 0
        let draftingNote = metadata?.draftingNote

        VStack(spacing: 12) {
            if isGeneratingDraft {
                VStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.8)
                        .tint(.purple)
                    Text("Generating AI Draft...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.6))
                    Text("Analyzing swipe patterns and building your first draft")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.3))
                }
                .padding(.vertical, 24)
            } else if hasDraftReady {
                Button(action: { generateAIDraft() }) {
                    aiDraftButtonLabel
                }
                .buttonStyle(.plain)
            } else if swipeCount > 0 {
                // Insufficient swipes
                VStack(spacing: 6) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.2))
                    Text(draftingNote ?? "Capture more swipes to unlock AI drafting (\(swipeCount)/3)")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.35))
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 12)
            }

            if let error = draftGenerationError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(.orange.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var aiDraftButtonLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .medium))
            Text("Generate AI Draft")
                .font(.system(size: 14, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.purple)
                .shadow(color: .purple.opacity(0.3), radius: 8, y: 4)
        )
    }

    private func generateAIDraft() {
        isGeneratingDraft = true
        draftGenerationError = nil

        Task {
            let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
            let swipeUUIDs = metadata?.inheritedSwipeUUIDs ?? []

            // Load the source idea if available
            var ideaAtom: Atom?
            if let ideaUUID = metadata?.sourceIdeaUUID {
                ideaAtom = try? await AtomRepository.shared.fetch(uuid: ideaUUID)
            }

            // Load matching swipe atoms
            var swipeAtoms: [Atom] = []
            for uuid in swipeUUIDs.prefix(5) {
                if let swipe = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    swipeAtoms.append(swipe)
                }
            }

            // Determine target format
            let format: ContentFormat = {
                if let platform = metadata?.platform {
                    switch platform {
                    case .twitter: return .tweet
                    case .instagram: return .reel
                    case .youtube: return .youtube
                    case .tiktok: return .reel
                    case .linkedin: return .post
                    default: return .post
                    }
                }
                return .post
            }()

            // Load client profile
            var clientProfile: Atom?
            if let clientUUID = metadata?.clientProfileUUID {
                clientProfile = try? await AtomRepository.shared.fetch(uuid: clientUUID)
            }

            // Generate via SwipeDraftEngine
            let sourceAtom = ideaAtom ?? atom
            guard let draftPackage = await SwipeDraftEngine.shared.generateDraftPackage(
                idea: sourceAtom,
                targetFormat: format,
                matchingSwipes: swipeAtoms,
                clientProfile: clientProfile
            ) else {
                await MainActor.run {
                    isGeneratingDraft = false
                    draftGenerationError = "Draft generation failed. Try again."
                }
                return
            }

            // Generate first draft text
            let firstDraft = await SwipeDraftEngine.shared.generateFirstDraft(
                idea: sourceAtom,
                draftPackage: draftPackage,
                targetFormat: format
            )

            await MainActor.run {
                if let draft = firstDraft, !draft.isEmpty {
                    state.draftContent = draft
                }
                // Populate outline from draft package
                if !draftPackage.suggestedOutline.isEmpty {
                    state.outline = draftPackage.suggestedOutline.enumerated().map { i, item in
                        OutlineItem(
                            title: item.title,
                            reasoning: item.description,
                            sortOrder: i,
                            isCompleted: false
                        )
                    }
                }
                state.save()
                isGeneratingDraft = false
                triggerAutoSave()
            }
        }
    }

    // MARK: - Sidebar Toggle Button

    @ViewBuilder
    private var sidebarToggleButton: some View {
        VStack {
            HStack {
                Button(action: {
                    withAnimation(ProMotionSprings.snappy) {
                        isSidebarVisible = true
                    }
                }) {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(CosmoColors.thinkspaceTertiary)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                        )
                }
                .buttonStyle(.plain)
                .padding(.leading, 16)
                .padding(.top, 16)
                Spacer()
            }
            Spacer()
        }
    }

    // MARK: - Sparkle Button

    @ViewBuilder
    private var sparkleButton: some View {
        Button(action: {
            let draft = state.draftContent
            if draft.isEmpty {
                selectedText = ""
            } else {
                let paragraphs = draft.components(separatedBy: "\n\n").filter { !$0.isEmpty }
                selectedText = paragraphs.last ?? String(draft.suffix(500))
            }
            showAIAssistant = true
        }) {
            Image(systemName: "sparkles")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(
                    Circle()
                        .fill(Color.purple)
                        .shadow(color: .purple.opacity(0.4), radius: 8, y: 4)
                )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 24)
        .padding(.bottom, 24)
    }

    // MARK: - Inline Action Bar

    @ViewBuilder
    private var inlineActionBar: some View {
        HStack(spacing: 2) {
            inlineBarButton(icon: "arrow.up.left.and.arrow.down.right", label: "Expand", action: .expand)
            inlineBarButton(icon: "arrow.down.right.and.arrow.up.left", label: "Condense", action: .condense)
            inlineBarButton(icon: "arrow.triangle.2.circlepath", label: "Rephrase", action: .rephrase)

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 1, height: 20)
                .padding(.horizontal, 2)

            // Custom prompt / overflow
            Button(action: {
                withAnimation(ProMotionSprings.snappy) {
                    showCustomPrompt.toggle()
                }
            }) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 12, y: 6)
        )
        .overlay(alignment: .bottom) {
            if showCustomPrompt {
                customPromptField
                    .offset(y: 46)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func inlineBarButton(icon: String, label: String, action: AIWritingAction) -> some View {
        Button(action: { triggerInlineAction(action) }) {
            inlineBarButtonLabel(icon: icon, label: label)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func inlineBarButtonLabel(icon: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.8))
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
        )
        .contentShape(Rectangle())
    }

    // MARK: - Custom Prompt Field

    @ViewBuilder
    private var customPromptField: some View {
        HStack(spacing: 6) {
            Image(systemName: "text.bubble")
                .font(.system(size: 11))
                .foregroundColor(.purple.opacity(0.7))

            TextField("Custom instruction...", text: $customPromptText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.9))
                .onSubmit {
                    guard !customPromptText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    triggerCustomPrompt(customPromptText)
                    customPromptText = ""
                    showCustomPrompt = false
                }

            Button(action: {
                guard !customPromptText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                triggerCustomPrompt(customPromptText)
                customPromptText = ""
                showCustomPrompt = false
            }) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.4), radius: 8, y: 4)
        )
    }

    // MARK: - Inline Result Popover

    @ViewBuilder
    private var inlineResultPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            inlineResultHeader

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            // Body
            if inlineAssistant.isProcessing {
                inlineProcessingView
            } else if let result = inlineAssistant.currentResult {
                inlineResultBody(result)
            } else if let error = inlineAssistant.error {
                inlineErrorView(error)
            }
        }
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.11))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.5), radius: 16, y: 8)
        )
    }

    @ViewBuilder
    private var inlineResultHeader: some View {
        HStack {
            Image(systemName: "sparkles")
                .foregroundColor(.purple)
                .font(.system(size: 12))
            Text("AI Suggestion")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            Spacer()
            Button(action: { dismissInlineAI() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.white.opacity(0.3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var inlineProcessingView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .scaleEffect(0.7)
                .tint(.purple)
            Text("Generating...")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    @ViewBuilder
    private func inlineResultBody(_ result: AIWritingResult) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Action tag
            HStack(spacing: 4) {
                Image(systemName: result.action.iconName)
                    .font(.system(size: 10))
                    .foregroundColor(.purple)
                Text(result.action.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.purple)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(Color.purple.opacity(0.15))
            )

            // Diff or result text
            if result.action == .rephrase, let variants = result.variants, !variants.isEmpty {
                inlineRephraseVariants(variants, result: result)
            } else if result.action == .continueWriting {
                inlineContinuationPreview(result)
            } else {
                inlineDiffPreview(result)
            }

            // Accept / Reject
            HStack(spacing: 8) {
                Button(action: { acceptInlineResult(result) }) {
                    inlineAcceptButtonLabel
                }
                .buttonStyle(.plain)

                Button(action: { dismissInlineAI() }) {
                    inlineRejectButtonLabel
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var inlineAcceptButtonLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .semibold))
            Text("Accept")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.purple)
        )
    }

    @ViewBuilder
    private var inlineRejectButtonLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .semibold))
            Text("Reject")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.5))
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.06))
        )
    }

    @State private var selectedRephraseIndex: Int = 0

    @ViewBuilder
    private func inlineRephraseVariants(_ variants: [String], result: AIWritingResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(variants.enumerated()), id: \.offset) { index, variant in
                    Button(action: { selectedRephraseIndex = index }) {
                        inlineVariantRow(index: index, variant: variant)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxHeight: 140)
    }

    @ViewBuilder
    private func inlineVariantRow(index: Int, variant: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: selectedRephraseIndex == index ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(selectedRephraseIndex == index ? .purple : .white.opacity(0.3))
                .padding(.top, 1)

            Text(variant)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selectedRephraseIndex == index ? Color.purple.opacity(0.12) : Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(selectedRephraseIndex == index ? Color.purple.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func inlineDiffPreview(_ result: AIWritingResult) -> some View {
        let diffWords = inlineAssistant.computeWordDiff(
            original: result.originalText,
            suggested: result.suggestedText
        )
        ScrollView {
            InlineDiffText(words: diffWords)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
    }

    @ViewBuilder
    private func inlineContinuationPreview(_ result: AIWritingResult) -> some View {
        let continuation = String(result.suggestedText.dropFirst(result.originalText.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        ScrollView {
            Text(continuation)
                .font(.system(size: 11))
                .foregroundColor(.green.opacity(0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: 120)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
    }

    @ViewBuilder
    private func inlineErrorView(_ errorMessage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 16))
                .foregroundColor(.orange)
            Text(errorMessage)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))
                .multilineTextAlignment(.center)
            Button(action: { dismissInlineAI() }) {
                Text("Dismiss")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.purple)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
    }

    // MARK: - Bottom Status Bar (context info only — navigation is in unified bottom bar)

    private var bottomBar: some View {
        HStack(spacing: 16) {
            // Phase indicator
            HStack(spacing: 6) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 10))
                    .foregroundColor(CosmoColors.blockContent)
                Text("Draft")
                    .font(CosmoTypography.caption)
                    .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            // Word count + save status
            HStack(spacing: 12) {
                if saveState != .idle {
                    HStack(spacing: 4) {
                        if saveState == .saving {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white.opacity(0.4))
                        } else {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(CosmoColors.blockContent)
                        }
                        Text(saveState == .saving ? "Saving..." : "Saved")
                            .font(CosmoTypography.caption)
                            .foregroundColor(.white.opacity(0.4))
                    }
                    .transition(.opacity)
                }

                Text("\(wordCount) words")
                    .font(CosmoTypography.caption)
                    .foregroundColor(.white.opacity(0.3))

                Text("\(state.completedOutlineCount)/\(state.outline.count) outline")
                    .font(CosmoTypography.caption)
                    .foregroundColor(.white.opacity(0.3))
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.03))
    }

    // MARK: - Helpers

    private var wordCount: Int {
        state.draftContent
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .count
    }

    private func relatedTypeColor(_ type: AtomType) -> Color {
        switch type {
        case .idea: return CosmoColors.blockNote
        case .research: return CosmoColors.blockResearch
        case .connection: return CosmoColors.blockConnection
        case .content: return CosmoColors.blockContent
        default: return .white.opacity(0.5)
        }
    }

    // MARK: - Selection Change Handler

    private func handleSelectionChange(_ info: DraftSelectionInfo) {
        selectionInfo = info

        if info.text.isEmpty || info.range.length == 0 {
            // Selection cleared — dismiss bar (but NOT if showing result)
            if inlineAIState == .showingBar {
                withAnimation(ProMotionSprings.snappy) {
                    inlineAIState = .idle
                    showCustomPrompt = false
                }
            }
        } else {
            // Has selection — show bar (unless processing/showing result)
            if inlineAIState == .idle {
                withAnimation(ProMotionSprings.snappy) {
                    inlineAIState = .showingBar
                }
            }
        }
    }

    // MARK: - Inline AI Actions

    private func triggerInlineAction(_ action: AIWritingAction) {
        let text = selectionInfo.text
        guard !text.isEmpty else { return }

        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .processing(action)
            showCustomPrompt = false
        }

        if action == .rephrase {
            selectedRephraseIndex = 0
        }

        Task {
            switch action {
            case .expand:
                _ = await inlineAssistant.expand(text: text, context: surroundingContext())
            case .condense:
                _ = await inlineAssistant.condense(text: text, context: surroundingContext())
            case .rephrase:
                _ = await inlineAssistant.rephrase(text: text, context: surroundingContext())
            case .continueWriting:
                let outlineTexts = state.outline.filter { !$0.isCompleted }.map(\.text)
                _ = await inlineAssistant.continueWriting(
                    text: text,
                    outline: outlineTexts,
                    coreIdea: state.coreIdea
                )
            }

            await MainActor.run {
                withAnimation(ProMotionSprings.snappy) {
                    inlineAIState = .showingResult
                }
            }
        }
    }

    private func triggerCustomPrompt(_ prompt: String) {
        let text = selectionInfo.text
        guard !text.isEmpty else { return }

        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .processing(.rephrase)
        }

        Task {
            // Use rephrase with custom instruction via expand endpoint
            _ = await inlineAssistant.expand(text: text, context: "Custom instruction: \(prompt)")

            await MainActor.run {
                withAnimation(ProMotionSprings.snappy) {
                    inlineAIState = .showingResult
                }
            }
        }
    }

    private func surroundingContext() -> String? {
        let draft = state.draftContent
        guard draft.count > 200 else { return draft }
        // Provide surrounding ~500 chars for context
        let nsString = draft as NSString
        let selRange = selectionInfo.range
        let contextStart = max(0, selRange.location - 250)
        let contextEnd = min(nsString.length, selRange.location + selRange.length + 250)
        let contextRange = NSRange(location: contextStart, length: contextEnd - contextStart)
        return nsString.substring(with: contextRange)
    }

    private func acceptInlineResult(_ result: AIWritingResult) {
        let originalText = result.originalText
        let replacement: String

        if result.action == .rephrase, let variants = result.variants, selectedRephraseIndex < variants.count {
            replacement = variants[selectedRephraseIndex]
        } else {
            replacement = result.suggestedText
        }

        // Replace the selected text in the draft
        if result.action == .continueWriting {
            // Continue appends — use the full suggested text
            state.draftContent = replacement
        } else {
            // Replace selected portion
            let nsString = state.draftContent as NSString
            let range = selectionInfo.range
            if range.location + range.length <= nsString.length {
                state.draftContent = nsString.replacingCharacters(in: range, with: replacement)
            } else {
                // Fallback: simple string replace
                state.draftContent = state.draftContent.replacingOccurrences(of: originalText, with: replacement)
            }
        }

        triggerAutoSave()
        dismissInlineAI()
    }

    private func dismissInlineAI() {
        withAnimation(ProMotionSprings.snappy) {
            inlineAIState = .idle
            inlineAssistant.currentResult = nil
            inlineAssistant.error = nil
            showCustomPrompt = false
        }
    }

    // MARK: - Auto-save

    private func triggerAutoSave() {
        autoSaveTask?.cancel()
        autoSaveTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(autoSaveDelay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    withAnimation(ProMotionSprings.snappy) {
                        saveState = .saving
                    }
                    state.lastModified = Date()
                    state.save()

                    withAnimation(ProMotionSprings.snappy) {
                        saveState = .saved
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        withAnimation(ProMotionSprings.gentle) {
                            saveState = .idle
                        }
                    }
                }
            } catch {
                // Cancelled
            }
        }
    }
}

// MARK: - Draft Editor Text View (NSViewRepresentable)

/// Editable NSTextView wrapper that reports text changes and selection changes
/// including the screen-relative rect of the selection for positioning floating overlays.
struct DraftEditorTextView: NSViewRepresentable {
    @Binding var text: String
    let onSelectionChanged: (DraftSelectionInfo) -> Void
    let onTextChanged: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        // Typography
        textView.font = NSFont.systemFont(ofSize: 17, weight: .regular)
        textView.textColor = NSColor.white.withAlphaComponent(0.9)
        textView.insertionPointColor = NSColor.white

        // Paragraph style matching CosmoTypography.bodyLineSpacing
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 6
        textView.defaultParagraphStyle = paragraphStyle

        // Layout
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        // Delegate
        textView.delegate = context.coordinator

        // Set initial text
        textView.string = text

        // Background transparent
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Only update text if it differs (avoids cursor jump)
        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selectedRanges
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DraftEditorTextView
        private var isUpdating = false

        init(parent: DraftEditorTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            guard !isUpdating else { return }
            isUpdating = true
            parent.text = textView.string
            parent.onTextChanged()
            isUpdating = false
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let range = textView.selectedRange()

            if range.length == 0 {
                parent.onSelectionChanged(.empty)
                return
            }

            let selectedString = (textView.string as NSString).substring(with: range)

            // Compute the rect of the selection start for positioning
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                parent.onSelectionChanged(DraftSelectionInfo(
                    text: selectedString,
                    range: range,
                    rectInEditor: .zero
                ))
                return
            }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            // Convert from text view local to window coordinates, then to screen
            let rectInTextView = NSRect(
                x: boundingRect.origin.x + textView.textContainerInset.width,
                y: boundingRect.origin.y + textView.textContainerInset.height,
                width: boundingRect.width,
                height: boundingRect.height
            )

            // Convert to the scroll view's coordinate space for SwiftUI overlay positioning
            let rectInScrollView = textView.convert(rectInTextView, to: textView.enclosingScrollView)

            let info = DraftSelectionInfo(
                text: selectedString,
                range: range,
                rectInEditor: CGRect(
                    x: rectInScrollView.origin.x,
                    y: rectInScrollView.origin.y,
                    width: rectInScrollView.width,
                    height: rectInScrollView.height
                )
            )

            parent.onSelectionChanged(info)
        }
    }
}

// MARK: - Inline Diff Text

/// Lightweight word-level diff display for inline result popover.
private struct InlineDiffText: View {
    let words: [DiffWord]

    var body: some View {
        words.enumerated().reduce(Text("")) { result, pair in
            let w = pair.element
            let separator = pair.offset == 0 ? Text("") : Text(" ")
            switch w.type {
            case .unchanged:
                return result + separator + Text(w.text)
                    .foregroundColor(.white.opacity(0.6))
            case .removed:
                return result + separator + Text(w.text)
                    .foregroundColor(.red.opacity(0.7))
                    .strikethrough(true, color: .red.opacity(0.5))
            case .added:
                return result + separator + Text(w.text)
                    .foregroundColor(.green.opacity(0.85))
            }
        }
        .font(.system(size: 11))
    }
}
