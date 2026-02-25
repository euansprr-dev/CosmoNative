// CosmoOS/UI/FocusMode/Ideas/IdeaFocusModeView.swift
// 2-column brainstorm workspace for ideas -- left: editing, right: intelligence panel
// February 2026

import SwiftUI
import AppKit
import Combine

// MARK: - Idea Focus Mode View

/// Full-screen brainstorm workspace that opens when a user taps an idea.
/// Left column: editable title, body, status pipeline, format/platform selectors, tags.
/// Right column: AI analysis panel with matching swipes, frameworks, hooks, and blueprint.
struct IdeaFocusModeView: View {
    // MARK: - Properties

    let atom: Atom
    let onClose: () -> Void

    // MARK: - State

    @StateObject private var viewModel: IdeaFocusModeViewModel
    @State private var newTagText: String = ""
    @State private var newIdeaHookText: String = ""
    @State private var showClientPicker: Bool = false
    @State private var showProfileEditor: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isTagFieldFocused: Bool
    @FocusState private var isDescriptionFocused: Bool

    // MARK: - Hover States

    @State private var hoveredPlatform: IdeaPlatform?
    @State private var hoveredStatus: IdeaStatus?

    // MARK: - Constants

    private let accentIndigo = DS.accent
    private let panelBackground = DS.surface
    private let cardBackground = DS.border
    private let ideaGold = OnyxColors.Accent.amber

    // MARK: - Initialization

    init(atom: Atom, onClose: @escaping () -> Void) {
        self.atom = atom
        self.onClose = onClose
        _viewModel = StateObject(wrappedValue: IdeaFocusModeViewModel(atom: atom))
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            DS.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        leftColumn
                            .frame(width: viewModel.sessionState.intelligencePanelCollapsed
                                   ? geo.size.width
                                   : geo.size.width * 0.65)

                        if !viewModel.sessionState.intelligencePanelCollapsed {
                            Rectangle()
                                .fill(DS.border)
                                .frame(width: 1)

                            rightColumn
                                .frame(width: geo.size.width * 0.35)
                                .transition(.move(edge: .trailing).combined(with: .opacity))
                        }
                    }
                }
            }

            // Overlay presentations
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
        }
        .onAppear {
            // Register context provider for global Cosmo window
            let provider = IdeaContextProvider(atom: atom, viewModel: viewModel)
            CosmoWindowViewModel.shared.updateContext(provider: provider)
        }
        .onDisappear {
            viewModel.saveOnClose()
        }
        .onKeyPress(.escape) {
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
        .sheet(isPresented: $showProfileEditor) {
            ContentProfileEditor(existingAtom: nil) { newProfile in
                Task { await viewModel.assignClient(newProfile) }
                Task { await viewModel.loadClientProfiles() }
            }
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(DS.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(DS.border, in: Capsule())
            }
            .buttonStyle(.plain)

            // Type badge
            HStack(spacing: 4) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 10))
                Text("Idea")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(OnyxTypography.labelTracking)
            }
            .foregroundColor(ideaGold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(ideaGold.opacity(0.12), in: Capsule())

            // Status badge
            if viewModel.selectedStatus != .spark {
                HStack(spacing: 4) {
                    Image(systemName: viewModel.selectedStatus.iconName)
                        .font(.system(size: 9))
                    Text(viewModel.selectedStatus.displayName.uppercased())
                        .font(.system(size: 8, weight: .bold))
                        .tracking(0.6)
                }
                .foregroundColor(viewModel.selectedStatus.color)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(viewModel.selectedStatus.color.opacity(0.15), in: Capsule())
            }

            Spacer()

            // Analyze button (header shortcut)
            Button {
                Task { await viewModel.analyzeIdea() }
            } label: {
                HStack(spacing: 6) {
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.6)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 12))
                    }
                    Text("Analyze")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(accentIndigo, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAnalyzing)
            .opacity(viewModel.isAnalyzing ? 0.7 : 1)

            // Toggle intelligence panel
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.sessionState.intelligencePanelCollapsed.toggle()
                    viewModel.sessionState.save()
                }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundColor(DS.textSecondary)
                    .padding(8)
                    .background(DS.border, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(DS.bg.opacity(0.95))
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Editable title
                titleEditor
                    .padding(.bottom, 24)

                // Hooks
                ideaHooksSection
                    .padding(.bottom, 24)

                // Section divider
                sectionDivider

                // Description (replaces Core Idea + old Description)
                ideaDescriptionSection
                    .padding(.bottom, 24)

                // Section divider
                sectionDivider

                // Status pipeline
                statusPipeline
                    .padding(.bottom, 24)

                // Section divider
                sectionDivider

                // Format selector
                formatSelector
                    .padding(.bottom, 24)

                // Section divider
                sectionDivider

                // Platform selector
                platformSelector
                    .padding(.bottom, 24)

                // Section divider
                sectionDivider

                // Client assignment
                clientAssignment
                    .padding(.bottom, 24)

                // Section divider
                sectionDivider

                // Tags editor
                tagsEditor

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 48)
            .padding(.top, 28)
        }
    }

    /// Thin divider between sections
    private var sectionDivider: some View {
        Rectangle()
            .fill(DS.border)
            .frame(height: 1)
            .padding(.bottom, 24)
    }

    // MARK: - Title Editor

    private var titleEditor: some View {
        TextField("Idea title...", text: $viewModel.editableTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(DS.text)
            .focused($isTitleFocused)
            .onChange(of: viewModel.editableTitle) { _ in
                viewModel.scheduleAutoSave()
            }
    }

    // MARK: - Hooks Section

    private var ideaHooksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("HOOKS")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.textMuted)
                    .tracking(1.2)

                Spacer()

                if !viewModel.editableHooks.isEmpty {
                    Text("\(viewModel.editableHooks.count) hooks")
                        .font(CosmoTypography.caption)
                        .foregroundColor(DS.textMuted)
                }
            }

            Text("Opening lines that grab attention")
                .font(.system(size: 13))
                .foregroundColor(DS.textSecondary)

            // Existing hooks
            ForEach(Array(viewModel.editableHooks.enumerated()), id: \.offset) { index, hook in
                IdeaHookRow(
                    hook: hook,
                    index: index,
                    onUpdate: { newText in
                        viewModel.editableHooks[index] = newText
                        viewModel.scheduleAutoSave()
                    },
                    onDelete: {
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.editableHooks.remove(at: index)
                            viewModel.scheduleAutoSave()
                        }
                    }
                )
            }

            // Add new hook
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(DS.accent.opacity(0.6))

                TextField("Add a hook...", text: $newIdeaHookText)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.body)
                    .foregroundColor(DS.text)
                    .onSubmit {
                        let trimmed = newIdeaHookText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.editableHooks.append(trimmed)
                            newIdeaHookText = ""
                            viewModel.scheduleAutoSave()
                        }
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(DS.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Description Section

    private var ideaDescriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DESCRIPTION")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
                .tracking(1.2)

            ZStack(alignment: .leading) {
                // Left accent bar
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(viewModel.selectedStatus.color)
                        .frame(width: 2)
                        .padding(.vertical, 12)
                    Spacer()
                }

                VStack(alignment: .trailing, spacing: 0) {
                    TextEditor(text: $viewModel.editableBody)
                        .scrollContentBackground(.hidden)
                        .font(.system(size: 15, weight: .regular))
                        .lineSpacing(15 * 0.6)
                        .foregroundColor(DS.text)
                        .frame(minHeight: 200, maxHeight: 400)
                        .padding(.leading, 18)
                        .padding(.trailing, 16)
                        .padding(.vertical, 16)
                        .focused($isDescriptionFocused)
                        .onChange(of: viewModel.editableBody) { _ in
                            viewModel.scheduleAutoSave()
                            viewModel.autoEnrich()
                        }

                    // Word count bottom-right
                    Text("\(viewModel.editableBody.split(separator: " ").count) words")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.textMuted)
                        .padding(.trailing, 16)
                        .padding(.bottom, 12)
                }
            }
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(DS.border, lineWidth: 1)
            )
            .overlay(alignment: .topLeading) {
                if viewModel.editableBody.isEmpty {
                    Text("What's the core idea? Include the hook angle, key points, and why this matters...")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundColor(DS.textMuted)
                        .lineSpacing(15 * 0.6)
                        .padding(.leading, 18)
                        .padding(.top, 16)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    // MARK: - Status Pipeline

    private var statusPipeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("STATUS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
                .tracking(1.2)

            statusPillsRow
        }
    }

    private var statusPillsRow: some View {
        HStack(spacing: 8) {
            ForEach(IdeaStatus.allCases, id: \.self) { status in
                Button {
                    Task { await viewModel.updateStatus(status) }
                } label: {
                    statusButtonLabel(for: status)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func statusButtonLabel(for status: IdeaStatus) -> some View {
        let isSelected = status == viewModel.selectedStatus
        let isHovered = hoveredStatus == status
        let bgColor: Color = isSelected
            ? status.color.opacity(0.3)
            : (isHovered ? DS.borderActive : DS.border)
        let strokeColor: Color = isSelected ? status.color.opacity(0.5) : Color.clear

        HStack(spacing: 5) {
            Image(systemName: status.iconName)
                .font(.system(size: 10))
            Text(status.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
        }
        .foregroundColor(isSelected ? .white : status.color.opacity(0.8))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(bgColor, in: Capsule())
        .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
        .shadow(
            color: isSelected ? status.color.opacity(0.3) : .clear,
            radius: 8, x: 0, y: 0
        )
        .onHover { hovering in
            withAnimation(OnyxSpring.hover) {
                hoveredStatus = hovering ? status : nil
            }
        }
    }

    // MARK: - Format Selector

    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FORMAT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
                .tracking(1.2)

            formatGroupRow(label: "Short-Form Video", formats: ContentFormat.shortFormVideo)
            formatGroupRow(label: "Static", formats: ContentFormat.staticFormats)
            formatGroupRow(label: "Text", formats: ContentFormat.textFormats)
            formatGroupRow(label: "Long-Form", formats: ContentFormat.longFormFormats)

            formatInsightHint
        }
    }

    @ViewBuilder
    private func formatGroupRow(label: String, formats: [ContentFormat]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(DS.textMuted)

            FlowLayout(spacing: 6) {
                ForEach(formats, id: \.self) { format in
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.selectedFormat = viewModel.selectedFormat == format ? nil : format
                            viewModel.scheduleAutoSave()
                        }
                    } label: {
                        formatButtonLabel(for: format)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func formatButtonLabel(for format: ContentFormat) -> some View {
        let isSelected = viewModel.selectedFormat == format

        HStack(spacing: 4) {
            Image(systemName: format.icon)
                .font(.system(size: 9))
            Text(format.displayName)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(isSelected ? format.color : DS.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected ? format.color.opacity(0.2) : DS.border,
            in: Capsule()
        )
    }

    @ViewBuilder
    private var formatInsightHint: some View {
        if let _ = viewModel.insight?.formatScores,
           let recommended = viewModel.insight?.recommendedFormat,
           let rationale = viewModel.insight?.formatRationale {
            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 10))
                    .foregroundColor(accentIndigo)
                Text("Recommended: \(ContentFormat(rawValue: recommended)?.displayName ?? recommended)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(accentIndigo)
                Text("-- \(rationale)")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Platform Selector

    private var platformSelector: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PLATFORM")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
                .tracking(1.2)

            HStack(spacing: 12) {
                ForEach(IdeaPlatform.allCases, id: \.self) { platform in
                    Button {
                        withAnimation(ProMotionSprings.snappy) {
                            viewModel.selectedPlatform = viewModel.selectedPlatform == platform ? nil : platform
                            viewModel.scheduleAutoSave()
                        }
                    } label: {
                        platformButtonLabel(for: platform)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func platformButtonLabel(for platform: IdeaPlatform) -> some View {
        let isSelected = viewModel.selectedPlatform == platform
        let isHovered = hoveredPlatform == platform

        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(
                        isSelected
                            ? platform.color.opacity(0.15)
                            : (isHovered ? DS.border : Color.clear)
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: platform.iconName)
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? platform.color : (isHovered ? DS.textSecondary : DS.textMuted))
            }

            Text(platform.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(isSelected ? platform.color : DS.textMuted)
        }
        .frame(width: 48)
        .onHover { hovering in
            withAnimation(OnyxSpring.hover) {
                hoveredPlatform = hovering ? platform : nil
            }
        }
    }

    // MARK: - Client Assignment

    private var clientAssignment: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CLIENT")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
                .tracking(1.2)

            HStack(spacing: 8) {
                if let client = viewModel.linkedClient {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(accentIndigo)
                        Text(client.title ?? "Client")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(DS.text)

                        Spacer()

                        Button {
                            Task { await viewModel.assignClient(nil) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13))
                                .foregroundColor(DS.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DS.border, lineWidth: 1)
                    )
                } else {
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
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .medium))
                            Text("Assign Client")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(DS.textMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .strokeBorder(
                                    DS.textMuted.opacity(0.4),
                                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                                )
                        )
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    // MARK: - Tags Editor

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("TAGS")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(DS.textMuted)
                .tracking(1.2)

            FlowLayout(spacing: 6) {
                ForEach(viewModel.tags, id: \.self) { tag in
                    HStack(spacing: 5) {
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.textSecondary)

                        Button {
                            viewModel.removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(DS.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(DS.border, in: Capsule())
                }

                // Add tag field
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(DS.textMuted)

                    TextField("Add tag", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(DS.text)
                        .frame(width: 80)
                        .focused($isTagFieldFocused)
                        .onSubmit {
                            viewModel.addTag(newTagText)
                            newTagText = ""
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.border, in: Capsule())
            }
        }
    }

    // MARK: - Right Column (Intelligence Panel)

    private var rightColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                // Panel header
                intelligencePanelHeader

                // Loading state
                if viewModel.isAnalyzing {
                    analysisLoadingView
                }

                // --- LINKED CONTEXT SECTIONS ---

                // 1. Related Swipes
                relatedSwipesSection

                // 2. Related Connections
                relatedConnectionsSection

                // 3. AI-Suggested Hooks (only when swipes linked)
                if !viewModel.linkedSwipes.isEmpty {
                    aiSuggestedHooksSection
                }

                // --- ANALYSIS SECTIONS ---

                // Recommended frameworks section
                if let frameworks = viewModel.insight?.frameworkRecommendations, !frameworks.isEmpty {
                    frameworksSection(frameworks)
                }

                // Format suitability
                if let formatScores = viewModel.insight?.formatScores, !formatScores.isEmpty {
                    formatSuitabilitySection(formatScores)
                }

                // Blueprint preview
                if let bp = viewModel.blueprint {
                    blueprintSection(bp)
                }

                // Empty state
                if viewModel.insight == nil && !viewModel.isAnalyzing
                    && viewModel.linkedSwipes.isEmpty && viewModel.linkedConnections.isEmpty {
                    emptyIntelligenceState
                }

                // "Activate This Idea" CTA
                if viewModel.insight != nil && !viewModel.isAnalyzing {
                    activateIdeaCTA
                }

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
        }
        .background(panelBackground)
    }

    // MARK: - Related Swipes Section

    private var relatedSwipesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with link button
            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc.fill")
                    .font(.system(size: 10))
                    .foregroundColor(accentIndigo)

                Text("RELATED SWIPES")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.textSecondary)
                    .tracking(0.8)

                Spacer()

                if !viewModel.linkedSwipes.isEmpty {
                    Text("\(viewModel.linkedSwipes.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(accentIndigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentIndigo.opacity(0.12), in: Capsule())
                }

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.showLinkSwipesOverlay = true
                    }
                } label: {
                    linkedSwipesLinkButtonLabel
                }
                .buttonStyle(.plain)
            }

            if viewModel.linkedSwipes.isEmpty {
                // Empty state
                Text("No swipes linked yet. Link swipes to give the AI structural inspiration when you draft this idea.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(viewModel.linkedSwipes, id: \.uuid) { swipe in
                    linkedSwipeCard(swipe)
                }
            }
        }
    }

    @ViewBuilder
    private var linkedSwipesLinkButtonLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
            Text("Link")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(accentIndigo)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentIndigo.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private func linkedSwipeCard(_ swipe: Atom) -> some View {
        let analysis = swipe.swipeAnalysis
        let hookText = swipe.researchMetadata?.hook ?? analysis?.hookText ?? ""
        let hookScore = analysis?.hookScore
        let hookType = analysis?.hookType

        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Thumbnail
                linkedSwipeThumbnail(swipe)

                VStack(alignment: .leading, spacing: 3) {
                    Text(swipe.title ?? "Untitled Swipe")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    // Hook text preview (60 chars)
                    if !hookText.isEmpty {
                        Text(String(hookText.prefix(60)))
                            .font(.system(size: 10))
                            .foregroundColor(DS.textSecondary)
                            .lineLimit(2)
                    }
                }

                Spacer()

                // Hook score badge
                if let score = hookScore {
                    linkedSwipeScoreBadge(score)
                }

                // Unlink button
                Button {
                    Task { await viewModel.unlinkSwipe(swipe.uuid) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.textMuted)
                        .padding(5)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Badge row: hook type + beat patterns
            HStack(spacing: 4) {
                if let type = hookType {
                    swipeHookTypePill(type)
                }
                if let platform = swipe.researchMetadata?.contentSource {
                    Text(platform)
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(DS.border, in: Capsule())
                }
            }
        }
        .padding(10)
        .background(DS.border, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func linkedSwipeThumbnail(_ swipe: Atom) -> some View {
        let thumbUrl = swipe.researchMetadata?.thumbnailUrl

        if let urlStr = thumbUrl, let url = URL(string: urlStr) {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                linkedSwipePlaceholderThumb
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            linkedSwipePlaceholderThumb
        }
    }

    @ViewBuilder
    private var linkedSwipePlaceholderThumb: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(DS.border)
            .frame(width: 40, height: 40)
            .overlay(
                Image(systemName: "doc.text")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textMuted)
            )
    }

    @ViewBuilder
    private func linkedSwipeScoreBadge(_ score: Double) -> some View {
        let color: Color = score >= 7 ? Color(hex: "22C55E") :
            score >= 5 ? Color(hex: "FBBF24") : Color(hex: "64748B")

        Text(String(format: "%.1f", score))
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Related Connections Section

    private var relatedConnectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with link button
            HStack(spacing: 6) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 10))
                    .foregroundColor(DS.accent)

                Text("RELATED CONNECTIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.textSecondary)
                    .tracking(0.8)

                Spacer()

                if !viewModel.linkedConnections.isEmpty {
                    Text("\(viewModel.linkedConnections.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(accentIndigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentIndigo.opacity(0.12), in: Capsule())
                }

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.showLinkConnectionsOverlay = true
                    }
                } label: {
                    relatedConnectionsLinkButtonLabel
                }
                .buttonStyle(.plain)
            }

            if viewModel.linkedConnections.isEmpty && viewModel.suggestedConnections.isEmpty {
                Text("No connections linked. Link your unique frameworks to make the content intellectually distinctive.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
            } else {
                // Linked connections
                ForEach(viewModel.linkedConnections, id: \.uuid) { conn in
                    linkedConnectionCard(conn)
                }

                // Suggested connections (dashed border)
                ForEach(viewModel.suggestedConnections, id: \.uuid) { conn in
                    suggestedConnectionCard(conn)
                }
            }
        }
    }

    @ViewBuilder
    private var relatedConnectionsLinkButtonLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
            Text("Link")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(accentIndigo)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentIndigo.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private func linkedConnectionCard(_ conn: Atom) -> some View {
        let maturity = resolveConnectionMaturity(conn)
        let filledCount = connectionFilledCount(conn)
        let filledNames = connectionFilledSectionNames(conn)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(conn.title ?? "Untitled Connection")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        connectionMaturityBadge(maturity)

                        Text("\(filledCount)/8 sections")
                            .font(.system(size: 9))
                            .foregroundColor(DS.textMuted)
                    }
                }

                Spacer()

                Button {
                    Task { await viewModel.unlinkConnection(conn.uuid) }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.textMuted)
                        .padding(5)
                        .background(DS.border, in: Circle())
                }
                .buttonStyle(.plain)
            }

            // Goal text preview
            if let goalText = connectionGoalPreview(conn), !goalText.isEmpty {
                Text(goalText)
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(2)
            }

            // Filled section names
            if !filledNames.isEmpty {
                Text(filledNames.joined(separator: " \u{2022} "))
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(DS.border, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func suggestedConnectionCard(_ conn: Atom) -> some View {
        let maturity = resolveConnectionMaturity(conn)
        let filledCount = connectionFilledCount(conn)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundColor(accentIndigo.opacity(0.6))

                Text(conn.title ?? "Untitled")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textSecondary)
                    .lineLimit(1)

                Spacer()

                connectionMaturityBadge(maturity)
            }

            Text("\(filledCount)/8 sections")
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)

            HStack(spacing: 8) {
                Button {
                    Task { await viewModel.linkConnection(conn.uuid) }
                } label: {
                    suggestedConnectionLinkLabel
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.suggestedConnections.removeAll { $0.uuid == conn.uuid }
                    }
                } label: {
                    suggestedConnectionDismissLabel
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    DS.borderActive,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 3])
                )
        )
    }

    @ViewBuilder
    private var suggestedConnectionLinkLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 9))
            Text("Link")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(accentIndigo)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentIndigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private var suggestedConnectionDismissLabel: some View {
        Text("Dismiss")
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(DS.textMuted)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(DS.border, in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func connectionMaturityBadge(_ level: ConnectionMaturityLevel) -> some View {
        let color = connectionMaturityColor(level)
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 5, height: 5)
            Text(level.displayName)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.3)
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    private func connectionMaturityColor(_ level: ConnectionMaturityLevel) -> Color {
        switch level {
        case .seed: return Color(hex: "9CA3AF")
        case .developing: return Color(hex: "FBBF24")
        case .mature: return Color(hex: "22C55E")
        case .proven: return Color(hex: "6366F1")
        }
    }

    private func resolveConnectionMaturity(_ conn: Atom) -> ConnectionMaturityLevel {
        if let cached = conn.connectionMaturityLevel,
           let level = ConnectionMaturityLevel(rawValue: cached) {
            return level
        }
        let count = connectionFilledCount(conn)
        if count >= 6 { return .proven }
        if count >= 4 { return .mature }
        if count >= 2 { return .developing }
        return .seed
    }

    private func connectionFilledCount(_ conn: Atom) -> Int {
        guard let structured = conn.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return 0
        }
        return data.sections.filter { !$0.items.isEmpty }.count
    }

    private func connectionFilledSectionNames(_ conn: Atom) -> [String] {
        guard let structured = conn.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return []
        }
        return data.sections
            .filter { !$0.items.isEmpty }
            .map { $0.type.displayName }
    }

    private func connectionGoalPreview(_ conn: Atom) -> String? {
        guard let structured = conn.structured,
              let data = ConnectionStructuredData.fromJSON(structured) else {
            return conn.mentalModel?.goal
        }
        let goalSection = data.sections.first { $0.type == .goal }
        return goalSection?.items.first?.content
    }

    // MARK: - AI-Suggested Hooks Section

    private var aiSuggestedHooksSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .font(.system(size: 10))
                    .foregroundColor(accentIndigo)

                Text("AI-SUGGESTED HOOKS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(DS.textSecondary)
                    .tracking(0.8)

                Spacer()

                if !viewModel.generatedHooks.isEmpty {
                    Text("\(viewModel.generatedHooks.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(accentIndigo)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentIndigo.opacity(0.12), in: Capsule())
                }

                // Refresh button
                Button {
                    Task { await viewModel.generateHooksFromLinkedSwipes() }
                } label: {
                    aiHooksRefreshButtonLabel
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isGeneratingHooks)
            }

            if viewModel.isGeneratingHooks {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small).tint(accentIndigo)
                    Text("Generating hooks from linked swipes...")
                        .font(.system(size: 11))
                        .foregroundColor(DS.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else if viewModel.generatedHooks.isEmpty {
                Text("Link swipes above, then hooks will be generated from their structural patterns.")
                    .font(.system(size: 11))
                    .foregroundColor(DS.textMuted)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(viewModel.generatedHooks) { hook in
                    generatedHookCard(hook)
                }
            }
        }
    }

    @ViewBuilder
    private var aiHooksRefreshButtonLabel: some View {
        Image(systemName: viewModel.isGeneratingHooks ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(accentIndigo.opacity(viewModel.isGeneratingHooks ? 0.4 : 1))
            .padding(5)
            .background(accentIndigo.opacity(0.08), in: Circle())
    }

    @ViewBuilder
    private func generatedHookCard(_ hook: HookSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Hook text
            Text(hook.hookText)
                .font(.system(size: 12, weight: .regular))
                .foregroundColor(DS.text)
                .lineLimit(3)

            // Hook type + score row
            HStack(spacing: 6) {
                if let hookType = hook.hookType {
                    swipeHookTypePill(hookType)
                }

                if let score = hook.estimatedScore {
                    generatedHookScoreBadge(score)
                }
            }

            // Source swipe attribution
            if let source = hook.sourceSwipeTitle, !source.isEmpty {
                Text("Based on pattern from \(source)")
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
                    .italic()
            }

            // Use This button
            Button {
                viewModel.editableBody = hook.hookText + "\n\n" + viewModel.editableBody
                viewModel.scheduleAutoSave()
            } label: {
                generatedHookUseLabel
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(DS.border, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(DS.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func generatedHookScoreBadge(_ score: Double) -> some View {
        let color: Color = score >= 7 ? Color(hex: "22C55E") :
            score >= 5 ? Color(hex: "3B82F6") : Color(hex: "64748B")

        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(String(format: "%.1f", score))
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    @ViewBuilder
    private var generatedHookUseLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.insert")
                .font(.system(size: 9))
            Text("Use This")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(accentIndigo)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(accentIndigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Intelligence Panel Header

    private var intelligencePanelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(accentIndigo)

                Text("Intelligence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                if let lastAnalyzed = viewModel.sessionState.lastAnalyzedAt {
                    Text("Last analyzed: \(formatRelativeDate(lastAnalyzed))")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                }
            }

            // Analyze button (main)
            Button {
                Task { await viewModel.analyzeIdea() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isAnalyzing {
                        ProgressView()
                            .scaleEffect(0.7)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 13))
                    }
                    Text(viewModel.insight == nil ? "Analyze Idea" : "Re-analyze")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [accentIndigo, accentIndigo.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: RoundedRectangle(cornerRadius: 8)
                )
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isAnalyzing)
            .opacity(viewModel.isAnalyzing ? 0.7 : 1)
        }
    }

    // MARK: - Analysis Loading

    private var analysisLoadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(accentIndigo)
                .scaleEffect(1.2)

            if !viewModel.analysisStage.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(viewModel.analysisStage)
                        .font(.system(size: 12))
                        .foregroundColor(DS.textSecondary)
                }
            } else {
                Text("Analyzing idea against swipe library...")
                    .font(.system(size: 12))
                    .foregroundColor(DS.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Text("Finding matching frameworks, hooks, and patterns")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // (Old matchingSwipesSection removed — replaced by relatedSwipesSection)

    @ViewBuilder
    private func swipeHookTypePill(_ hookType: SwipeHookType) -> some View {
        HStack(spacing: 3) {
            Image(systemName: hookType.iconName)
                .font(.system(size: 8))
            Text(hookType.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundColor(hookType.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(hookType.color.opacity(0.15), in: Capsule())
    }

    // MARK: - Frameworks Section

    private func frameworksSection(_ frameworks: [FrameworkRecommendation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "RECOMMENDED FRAMEWORKS", count: frameworks.count, icon: "rectangle.3.group.fill")

            ForEach(frameworks.prefix(3)) { rec in
                frameworkCard(rec)
            }
        }
    }

    private func frameworkCard(_ rec: FrameworkRecommendation) -> some View {
        let isSelected = viewModel.sessionState.selectedFramework == rec.framework.rawValue

        return VStack(alignment: .leading, spacing: 8) {
            // Name + confidence
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rec.framework.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(DS.text)

                    Text(rec.framework.description)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(1)
                }

                Spacer()
            }

            // Confidence bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Confidence")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                    Spacer()
                    Text("\(Int(rec.confidence * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(accentIndigo)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(DS.borderActive)
                            .frame(height: OnyxLayout.progressLineHeight)

                        RoundedRectangle(cornerRadius: 1)
                            .fill(accentIndigo)
                            .frame(width: geo.size.width * rec.confidence, height: OnyxLayout.progressLineHeight)
                    }
                }
                .frame(height: OnyxLayout.progressLineHeight)
            }

            // Rationale
            Text(rec.rationale)
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)
                .lineLimit(3)

            // Evidence-based reasoning
            if let reasoning = rec.reasoning {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "lightbulb.min")
                        .font(.system(size: 9))
                        .foregroundColor(accentIndigo.opacity(0.6))
                        .padding(.top, 1)

                    Text(reasoning)
                        .font(.system(size: 10))
                        .foregroundColor(DS.textMuted)
                        .lineLimit(4)
                        .italic()
                }
                .padding(8)
                .background(accentIndigo.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
            }

            // Select button
            Button {
                Task { await viewModel.selectFramework(rec.framework) }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                        .font(.system(size: 11))
                    Text(isSelected ? "Selected" : "Select Framework")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(isSelected ? DS.green : accentIndigo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    (isSelected ? DS.green : accentIndigo).opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 6)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    isSelected ? accentIndigo.opacity(0.4) : Color.clear,
                    lineWidth: 1
                )
        )
    }

    // (Old hooksSection removed — replaced by aiSuggestedHooksSection)

    // MARK: - Blueprint Section

    private func blueprintSection(_ bp: ContentBlueprint) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(
                title: "CONTENT BLUEPRINT",
                count: bp.sections.count,
                icon: "doc.text.magnifyingglass"
            )

            // Suggested hook
            if let hook = bp.suggestedHook {
                VStack(alignment: .leading, spacing: 4) {
                    Text("HOOK")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(accentIndigo.opacity(0.7))
                        .tracking(0.6)

                    Text(hook)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .italic()
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accentIndigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // Blueprint sections
            ForEach(bp.sections.sorted(by: { $0.sortOrder < $1.sortOrder })) { section in
                blueprintSectionCard(section)
            }

            // Suggested CTA
            if let cta = bp.suggestedCTA {
                VStack(alignment: .leading, spacing: 4) {
                    Text("CALL TO ACTION")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(DS.green.opacity(0.7))
                        .tracking(0.6)

                    Text(cta)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // Word count estimate
            if let wordCount = bp.estimatedWordCount {
                HStack(spacing: 4) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 10))
                    Text("~\(wordCount) words estimated")
                        .font(.system(size: 10))
                }
                .foregroundColor(DS.textMuted)
            }

        }
    }

    private func blueprintSectionCard(_ section: BlueprintSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.text)

                Spacer()

                if let wordCount = section.targetWordCount {
                    Text("~\(wordCount)w")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(DS.textMuted)
                }
            }

            Text(section.purpose)
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)

            if let content = section.suggestedContent, !content.isEmpty {
                Text(content)
                    .font(.system(size: 11))
                    .foregroundColor(DS.textSecondary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Format Suitability Section

    private func formatSuitabilitySection(_ formatScores: [String: Double]) -> some View {
        let dataSources = viewModel.insight?.formatDataSources

        return VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "FORMAT SUITABILITY", count: formatScores.count, icon: "slider.horizontal.3")

            ForEach(formatScores.sorted(by: { $0.value > $1.value }), id: \.key) { key, score in
                VStack(alignment: .leading, spacing: 2) {
                    formatScoreBar(formatKey: key, score: score)

                    if let source = dataSources?[key] {
                        Text(source)
                            .font(.system(size: 9))
                            .foregroundColor(DS.textMuted)
                            .padding(.leading, 88)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func formatScoreBar(formatKey: String, score: Double) -> some View {
        let formatName = ContentFormat(rawValue: formatKey)?.displayName ?? formatKey
        let formatColor = ContentFormat(rawValue: formatKey)?.color ?? accentIndigo

        HStack(spacing: 8) {
            Text(formatName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(DS.textSecondary)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(DS.borderActive)
                        .frame(height: OnyxLayout.progressLineHeight)

                    RoundedRectangle(cornerRadius: 1)
                        .fill(formatColor.opacity(0.8))
                        .frame(width: geo.size.width * score, height: OnyxLayout.progressLineHeight)
                }
            }
            .frame(height: OnyxLayout.progressLineHeight)

            Text("\(Int(score * 100))%")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(formatColor)
                .frame(width: 32, alignment: .trailing)
        }
    }

    // MARK: - Activate Idea CTA

    private var activateIdeaCTA: some View {
        Button {
            Task { await viewModel.promoteToContent() }
        } label: {
            activateIdeaCTALabel()
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func activateIdeaCTALabel() -> some View {
        HStack {
            Image(systemName: "arrow.up.forward")
            Text("Activate This Idea")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(accentIndigo, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Empty Intelligence State

    private var emptyIntelligenceState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 32))
                .foregroundColor(accentIndigo.opacity(0.4))

            Text("No analysis yet")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(DS.textSecondary)

            Text("Click \"Analyze Idea\" to find matching swipes, recommended frameworks, and hook suggestions from your library.")
                .font(.system(size: 12))
                .foregroundColor(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineLimit(4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, 20)
    }

    // MARK: - Helpers

    private func sectionHeader(title: String, count: Int, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(accentIndigo)

            Text(title)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(DS.textSecondary)
                .tracking(0.8)

            Spacer()

            Text("\(count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(accentIndigo)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(accentIndigo.opacity(0.12), in: Capsule())
        }
    }

    private func formatRelativeDate(_ iso8601: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: iso8601) else { return iso8601 }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

// MARK: - Flow Layout

/// Simple horizontal wrapping layout for tags and chips.
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

// MARK: - Idea Hook Row

private struct IdeaHookRow: View {
    let hook: String
    let index: Int
    let onUpdate: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index + 1).")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(DS.textMuted)
                .frame(width: 20, alignment: .trailing)

            if isEditing {
                TextField("", text: $editText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.text)
                    .focused($isFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(hook)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(2)
                    .onTapGesture(count: 2) {
                        editText = hook
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer(minLength: 4)

            if isHovered {
                Button(action: {
                    editText = hook
                    isEditing = true
                    isFocused = true
                }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)

                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(DS.textMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(DS.borderSubtle)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private func commitEdit() {
        let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onUpdate(trimmed) }
        isEditing = false
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
