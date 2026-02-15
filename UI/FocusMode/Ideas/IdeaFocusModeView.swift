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
    @State private var showClientPicker: Bool = false
    @State private var showProfileEditor: Bool = false
    @FocusState private var isTitleFocused: Bool
    @FocusState private var isBodyFocused: Bool
    @FocusState private var isTagFieldFocused: Bool

    // MARK: - Constants

    private let accentIndigo = OnyxColors.Accent.iris
    private let panelBackground = OnyxColors.Elevation.base
    private let cardBackground = Color.white.opacity(0.06)
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
            CosmoColors.thinkspaceVoid
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar

                HStack(spacing: 0) {
                    leftColumn
                        .frame(maxWidth: .infinity)

                    Divider()
                        .background(Color.white.opacity(0.15))

                    if !viewModel.sessionState.intelligencePanelCollapsed {
                        rightColumn
                            .frame(width: 380)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        }
        .onDisappear {
            viewModel.saveOnClose()
        }
        .onKeyPress(.escape) {
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
        HStack(spacing: 16) {
            // Back button
            Button(action: onClose) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Back")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundColor(.white.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.08), in: Capsule())
            }
            .buttonStyle(.plain)

            // Title
            Text(viewModel.editableTitle.isEmpty ? "Untitled Idea" : viewModel.editableTitle)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)

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
                Image(systemName: viewModel.sessionState.intelligencePanelCollapsed
                      ? "sidebar.right"
                      : "sidebar.right")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .padding(8)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    CosmoColors.thinkspaceVoid.opacity(0.95),
                    CosmoColors.thinkspaceVoid.opacity(0.8),
                    CosmoColors.thinkspaceVoid.opacity(0.4),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
        , alignment: .top)
    }

    // MARK: - Left Column

    private var leftColumn: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                // Editable title
                titleEditor

                // Core idea body
                bodyEditor

                // Status pipeline
                statusPipeline

                // Format selector
                formatSelector

                // Platform selector
                platformSelector

                // Client assignment
                clientAssignment

                // Tags editor
                tagsEditor

                Spacer(minLength: 60)
            }
            .padding(.horizontal, 40)
            .padding(.top, 24)
        }
    }

    // MARK: - Title Editor

    private var titleEditor: some View {
        TextField("Idea title...", text: $viewModel.editableTitle)
            .textFieldStyle(.plain)
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.white)
            .focused($isTitleFocused)
            .onChange(of: viewModel.editableTitle) { _ in
                viewModel.scheduleAutoSave()
            }
    }

    // MARK: - Body Editor

    private var bodyEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CORE IDEA")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.0)

            TextEditor(text: $viewModel.editableBody)
                .scrollContentBackground(.hidden)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(.white.opacity(0.9))
                .frame(minHeight: 120, maxHeight: 240)
                .padding(12)
                .background(cardBackground, in: RoundedRectangle(cornerRadius: 10))
                .focused($isBodyFocused)
                .onChange(of: viewModel.editableBody) { _ in
                    viewModel.scheduleAutoSave()
                    viewModel.autoEnrich()
                }

            Text("\(viewModel.editableBody.split(separator: " ").count) words")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
    }

    // MARK: - Status Pipeline

    private var statusPipeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STATUS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.0)

            HStack(spacing: 6) {
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
    }

    @ViewBuilder
    private func statusButtonLabel(for status: IdeaStatus) -> some View {
        let isSelected = status == viewModel.selectedStatus
        let bgColor: Color = isSelected ? status.color.opacity(0.3) : Color.white.opacity(0.06)
        let strokeColor: Color = isSelected ? status.color.opacity(0.6) : Color.clear

        HStack(spacing: 4) {
            Image(systemName: status.iconName)
                .font(.system(size: 9))
            Text(status.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        }
        .foregroundColor(isSelected ? .white : status.color.opacity(0.8))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bgColor, in: Capsule())
        .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
    }

    // MARK: - Format Selector

    private var formatSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FORMAT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.0)

            formatGroupRow(label: "Short-Form Video", formats: ContentFormat.shortFormVideo)
            formatGroupRow(label: "Static", formats: ContentFormat.staticFormats)
            formatGroupRow(label: "Text", formats: ContentFormat.textFormats)
            formatGroupRow(label: "Long-Form", formats: ContentFormat.longFormFormats)

            formatInsightHint
        }
    }

    @ViewBuilder
    private func formatGroupRow(label: String, formats: [ContentFormat]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.white.opacity(0.3))

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
        let bgColor: Color = isSelected ? format.color.opacity(0.25) : Color.white.opacity(0.06)
        let strokeColor: Color = isSelected ? format.color.opacity(0.5) : Color.clear

        HStack(spacing: 4) {
            Image(systemName: format.icon)
                .font(.system(size: 9))
            Text(format.displayName)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
        }
        .foregroundColor(isSelected ? .white : format.color.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(bgColor, in: Capsule())
        .overlay(Capsule().stroke(strokeColor, lineWidth: 1))
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
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(1)
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Platform Selector

    private var platformSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PLATFORM")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.0)

            HStack(spacing: 8) {
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
        let bgColor: Color = isSelected ? platform.color.opacity(0.15) : Color.white.opacity(0.04)
        let strokeColor: Color = isSelected ? platform.color.opacity(0.4) : Color.clear

        VStack(spacing: 4) {
            Image(systemName: platform.iconName)
                .font(.system(size: 16))
                .foregroundColor(isSelected ? platform.color : .white.opacity(0.4))

            Text(platform.displayName)
                .font(.system(size: 8, weight: .medium))
                .foregroundColor(isSelected ? platform.color : .white.opacity(0.3))
        }
        .frame(width: 52, height: 48)
        .background(bgColor, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(strokeColor, lineWidth: 1))
    }

    // MARK: - Client Assignment

    private var clientAssignment: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLIENT")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.0)

            HStack(spacing: 8) {
                if let client = viewModel.linkedClient {
                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(accentIndigo)
                        Text(client.title ?? "Client")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)

                        Button {
                            Task { await viewModel.assignClient(nil) }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(cardBackground, in: Capsule())
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
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 12))
                            Text("Assign Client")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundColor(.white.opacity(0.5))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.white.opacity(0.06), in: Capsule())
                    }
                    .menuStyle(.borderlessButton)
                }
            }
        }
    }

    // MARK: - Tags Editor

    private var tagsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TAGS")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white.opacity(0.4))
                .tracking(1.0)

            // Existing tags as chips
            FlowLayout(spacing: 6) {
                ForEach(viewModel.tags, id: \.self) { tag in
                    HStack(spacing: 4) {
                        Text(tag)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.white.opacity(0.8))

                        Button {
                            viewModel.removeTag(tag)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundColor(.white.opacity(0.4))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1), in: Capsule())
                }

                // Add tag field
                HStack(spacing: 4) {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))

                    TextField("Add tag", text: $newTagText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .frame(width: 80)
                        .focused($isTagFieldFocused)
                        .onSubmit {
                            viewModel.addTag(newTagText)
                            newTagText = ""
                        }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.white.opacity(0.06), in: Capsule())
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

                // Matching swipes section
                if let swipes = viewModel.insight?.matchingSwipes, !swipes.isEmpty {
                    matchingSwipesSection(swipes)
                }

                // Recommended frameworks section
                if let frameworks = viewModel.insight?.frameworkRecommendations, !frameworks.isEmpty {
                    frameworksSection(frameworks)
                }

                // Suggested hooks section
                if let hooks = viewModel.insight?.hookSuggestions, !hooks.isEmpty {
                    hooksSection(hooks)
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
                if viewModel.insight == nil && !viewModel.isAnalyzing {
                    emptyIntelligenceState
                }

                // "Activate This Idea" CTA — shown after analysis completes
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

    // MARK: - Intelligence Panel Header

    private var intelligencePanelHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 14))
                    .foregroundColor(accentIndigo)

                Text("Intelligence")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if let lastAnalyzed = viewModel.sessionState.lastAnalyzedAt {
                    Text("Last analyzed: \(formatRelativeDate(lastAnalyzed))")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.3))
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
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                Text("Analyzing idea against swipe library...")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            Text("Finding matching frameworks, hooks, and patterns")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    // MARK: - Matching Swipes Section

    private func matchingSwipesSection(_ swipes: [SwipeMatch]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "MATCHING SWIPES", count: swipes.count, icon: "doc.on.doc.fill")

            ForEach(swipes.prefix(3)) { swipe in
                swipeMatchCard(swipe)
            }

            if swipes.count > 3 {
                Text("+\(swipes.count - 3) more matching swipes")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
        }
    }

    private func swipeMatchCard(_ swipe: SwipeMatch) -> some View {
        Button {
            // Open swipe in focus mode
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": swipe.swipeAtomUUID]
            )
        } label: {
            swipeMatchCardLabel(swipe)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func swipeMatchCardLabel(_ swipe: SwipeMatch) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title + similarity
            HStack {
                Text(swipe.title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(2)

                Spacer()

                Text("\(Int(swipe.similarityScore * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(similarityColor(swipe.similarityScore))
            }

            // Similarity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: OnyxLayout.progressLineHeight)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [
                                    similarityColor(swipe.similarityScore).opacity(0.6),
                                    similarityColor(swipe.similarityScore)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * swipe.similarityScore, height: OnyxLayout.progressLineHeight)
                }
            }
            .frame(height: OnyxLayout.progressLineHeight)

            // Badges
            HStack(spacing: 6) {
                if let hookType = swipe.hookType {
                    swipeHookTypePill(hookType)
                }

                if let framework = swipe.frameworkType {
                    HStack(spacing: 3) {
                        Text(framework.abbreviation)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(framework.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(framework.color.opacity(0.15), in: Capsule())
                }

                if let platform = swipe.platform {
                    Text(platform)
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                }
            }

            // Hook text preview
            if let hookText = swipe.hookText {
                Text("\"\(hookText)\"")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundColor(.white.opacity(0.5))
                    .italic()
                    .lineLimit(2)
            }

            // Match reason
            if let reason = swipe.matchReason {
                Text(reason)
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.4))
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 8))
    }

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
                        .foregroundColor(.white)

                    Text(rec.framework.description)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.4))
                        .lineLimit(1)
                }

                Spacer()
            }

            // Confidence bar
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Confidence")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.4))
                    Spacer()
                    Text("\(Int(rec.confidence * 100))%")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(accentIndigo)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(Color.white.opacity(0.1))
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
                .foregroundColor(.white.opacity(0.5))
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
                        .foregroundColor(.white.opacity(0.35))
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
                .foregroundColor(isSelected ? Color(hex: "#22C55E") : accentIndigo)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    (isSelected ? Color(hex: "#22C55E") : accentIndigo).opacity(0.12),
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

    // MARK: - Hooks Section

    private func hooksSection(_ hooks: [HookSuggestion]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(title: "HOOK VARIANTS", count: hooks.count, icon: "text.quote")

            ForEach(Array(hooks.prefix(5).enumerated()), id: \.element.id) { index, hook in
                hookVariantCard(hook, index: index)
            }
        }
    }

    private func hookVariantCard(_ hook: HookSuggestion, index: Int) -> some View {
        let isSelected = viewModel.selectedHookIndex == index

        return VStack(alignment: .leading, spacing: 8) {
            // Hook text
            Text(hook.hookText)
                .font(.system(size: 12, weight: isSelected ? .medium : .regular))
                .foregroundColor(isSelected ? .white : .white.opacity(0.7))
                .multilineTextAlignment(.leading)

            // Hook type badge
            if let hookType = hook.hookType {
                HStack(spacing: 3) {
                    Image(systemName: hookType.iconName)
                        .font(.system(size: 8))
                    Text(hookType.displayName)
                        .font(.system(size: 9, weight: .medium))
                }
                .foregroundColor(hookType.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(hookType.color.opacity(0.12), in: Capsule())
            }

            // Action buttons row
            HStack(spacing: 8) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hook.hookText, forType: .string)
                } label: {
                    hookVariantCopyLabel()
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.editableBody = hook.hookText + "\n\n" + viewModel.editableBody
                    viewModel.scheduleAutoSave()
                } label: {
                    hookVariantUseLabel()
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.selectedHookIndex = isSelected ? nil : index
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 14))
                        .foregroundColor(isSelected ? accentIndigo : .white.opacity(0.3))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(
            isSelected ? accentIndigo.opacity(0.08) : cardBackground,
            in: RoundedRectangle(cornerRadius: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? accentIndigo.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func hookVariantCopyLabel() -> some View {
        HStack(spacing: 3) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 9))
            Text("Copy")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white.opacity(0.5))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
    }

    @ViewBuilder
    private func hookVariantUseLabel() -> some View {
        HStack(spacing: 3) {
            Image(systemName: "text.insert")
                .font(.system(size: 9))
            Text("Use")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(accentIndigo)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(accentIndigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 5))
    }

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
                        .foregroundColor(.white.opacity(0.8))
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
                        .foregroundColor(Color(hex: "#22C55E").opacity(0.7))
                        .tracking(0.6)

                    Text(cta)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#22C55E").opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            // Word count estimate
            if let wordCount = bp.estimatedWordCount {
                HStack(spacing: 4) {
                    Image(systemName: "character.cursor.ibeam")
                        .font(.system(size: 10))
                    Text("~\(wordCount) words estimated")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white.opacity(0.3))
            }

        }
    }

    private func blueprintSectionCard(_ section: BlueprintSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(section.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()

                if let wordCount = section.targetWordCount {
                    Text("~\(wordCount)w")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.white.opacity(0.3))
                }
            }

            Text(section.purpose)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.5))

            if let content = section.suggestedContent, !content.isEmpty {
                Text(content)
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.7))
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
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
                            .foregroundColor(.white.opacity(0.25))
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
                .foregroundColor(.white.opacity(0.7))
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.white.opacity(0.1))
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
                .foregroundColor(.white.opacity(0.5))

            Text("Click \"Analyze Idea\" to find matching swipes, recommended frameworks, and hook suggestions from your library.")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
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
                .foregroundColor(.white.opacity(0.5))
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

    private func similarityColor(_ score: Double) -> Color {
        if score >= 0.8 { return Color(hex: "#22C55E") }
        if score >= 0.6 { return Color(hex: "#FBBF24") }
        return Color(hex: "#64748B")
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
