// CosmoOS/UI/FocusMode/Content/ContentOutlineSidebarContent.swift
// Content for the UniversalFocusSidebar when in content focus mode
// Core idea, hooks, outline + inherited context (source idea, swipes, framework, intelligence)
// February 2026 — March 2026: consolidated right context panel into left sidebar

import SwiftUI

// MARK: - Content Outline Sidebar Content

/// Provides the content for the left universal sidebar in Content Focus Mode.
/// Shows core idea (editable), hooks (editable + add), outline (draggable + checkmarks),
/// then inherited context: source idea, matched swipes, connections, framework, intelligence.
struct ContentOutlineSidebarContent: View {
    @Binding var state: ContentFocusModeState
    let atom: Atom
    var writingEngine: UnifiedWritingEngine?

    @State private var newHookText = ""
    @State private var newOutlineText = ""
    @State private var isGeneratingOpusOutline = false
    @State private var opusOutlineError: String?
    @FocusState private var coreIdeaFocused: Bool

    // Context data (ported from ContentContextPanel)
    @State private var sourceIdea: Atom?
    @State private var matchedSwipeAtoms: [Atom] = []
    @State private var inheritedConnectionAtoms: [Atom] = []
    @State private var selectedFramework: String?
    @State private var inheritedHooks: [String] = []
    @State private var relatedContent: [RelatedAtomRef] = []
    @State private var isLoadingRelated = false
    @State private var relatedSearchTask: Task<Void, Never>?
    @State private var metaPatternReport: MetaPatternReport?
    @State private var isLoadingMetaPattern = false
    @StateObject private var ambientEngine = AmbientFieldEngine()
    @State private var showAllSwipes = false
    @State private var showIntelligence = false
    @State private var isLoadingContext = true

    private let accentColor = CosmoMentionColors.content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Creation tools
                coreIdeaSection
                hooksSection
                outlineSection

                // Context divider
                if hasAnyContext {
                    contextDivider
                }

                // Inherited context sections
                sourceIdeaSection
                matchedSwipesSection
                inheritedConnectionsSection
                frameworkSection
                inheritedHooksSection

                // Codex-era panels (collapsible)
                // codexOutlinePanel removed — outlineSection handles both simple + advanced
                codexResearchPanel
                codexArcPanel
                codexContextDirectionPanel
                codexChatHistoryPanel
                codexQuickRefPanel

                intelligenceSection
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .onAppear {
            Task { await loadInheritedContext() }
            let queryText = [atom.title ?? "", String((atom.body ?? "").prefix(200))].joined(separator: " ")
            ambientEngine.updateContext(focusAtomUUID: atom.uuid, currentText: queryText)
        }
    }

    // MARK: - Context Divider

    private var contextDivider: some View {
        VStack(spacing: 8) {
            Rectangle()
                .fill(DS.border)
                .frame(height: 1)

            HStack(spacing: 6) {
                Image(systemName: "link.circle.fill")
                    .font(DS.caption2)
                    .foregroundStyle(accentColor)
                Text("CONTEXT")
                    .font(DS.caption2)
                    .tracking(0.8)
                    .foregroundStyle(DS.textMuted)
                Spacer()

                if isLoadingContext {
                    ProgressView()
                        .controlSize(.mini)
                        .tint(DS.textMuted)
                }
            }
        }
        .padding(.top, 4)
    }

    private var hasAnyContext: Bool {
        sourceIdea != nil
        || !matchedSwipeAtoms.isEmpty
        || !inheritedConnectionAtoms.isEmpty
        || (selectedFramework != nil && !selectedFramework!.isEmpty)
        || !inheritedHooks.isEmpty
        || hasIntelligenceData
        || isLoadingContext
    }

    private var hasIntelligenceData: Bool {
        metaPatternReport != nil
        || hasDraftIntelligence
        || !relatedContent.isEmpty
        || !ambientEngine.ambientResults.isEmpty
    }

    private var hasDraftIntelligence: Bool {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        let swipeUUIDs = metadata?.inheritedSwipeUUIDs ?? []
        return !swipeUUIDs.isEmpty
    }

    // MARK: - Core Idea Section

    private var coreIdeaSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CORE IDEA")
                .font(DS.sectionLabel)
                .foregroundStyle(DS.textMuted)
                .tracking(0.88)

            TextEditor(text: $state.coreIdea)
                .font(DS.callout)
                .foregroundStyle(DS.text)
                .lineSpacing(4)
                .scrollContentBackground(.hidden)
                .focused($coreIdeaFocused)
                .frame(minHeight: 48, maxHeight: 100)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .fill(DS.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.radiusSmall)
                                .stroke(
                                    coreIdeaFocused ? DS.borderActive : DS.border,
                                    lineWidth: 1
                                )
                        )
                )
                .onChange(of: state.coreIdea) { _, _ in
                    state.lastModified = Date()
                    state.save()
                }
        }
    }

    // MARK: - Hooks Section

    private var hooksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("HOOKS")
                    .font(DS.sectionLabel)
                    .foregroundStyle(DS.textMuted)
                    .tracking(0.88)

                Spacer()

                if !state.hooks.isEmpty {
                    Text("\(state.hooks.count)")
                        .font(DS.caption2)
                        .foregroundStyle(DS.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.accent.opacity(0.15), in: Capsule())
                }
            }

            // Existing hooks
            ForEach(Array(state.hooks.enumerated()), id: \.offset) { index, hook in
                SidebarHookRow(
                    hook: hook,
                    index: index,
                    onUpdate: { newText in
                        state.hooks[index] = newText
                        state.lastModified = Date()
                        state.save()
                    },
                    onDelete: {
                        withAnimation(ProMotionSprings.snappy) {
                            state.hooks.remove(at: index)
                            state.lastModified = Date()
                            state.save()
                        }
                    }
                )
            }

            // Add new hook
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.callout)
                    .foregroundStyle(DS.accent.opacity(0.5))

                TextField("Add a hook...", text: $newHookText)
                    .textFieldStyle(.plain)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.text)
                    .onSubmit { addHook() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    private func addHook() {
        let trimmed = newHookText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            state.hooks.append(trimmed)
            newHookText = ""
            state.lastModified = Date()
            state.save()
        }
    }

    // MARK: - Outline Section

    private var outlineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            outlineSectionHeader

            // AI-suggested badge
            if state.isAISuggestedOutline && !state.outline.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(DS.caption2)
                    Text("AI-suggested")
                        .font(DS.caption2)
                }
                .foregroundStyle(DS.accent.opacity(0.7))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.accent.opacity(0.1), in: Capsule())
            }

            // Outline items as checklist
            VStack(spacing: 2) {
                ForEach(state.sortedOutline) { item in
                    SidebarOutlineRow(
                        item: item,
                        onToggle: {
                            withAnimation(ProMotionSprings.snappy) {
                                state.toggleOutlineItem(id: item.id)
                                state.save()
                            }
                        },
                        onUpdateTitle: { title in
                            state.updateOutlineItem(id: item.id, title: title)
                            state.save()
                        },
                        onDelete: {
                            withAnimation(ProMotionSprings.snappy) {
                                state.removeOutlineItem(id: item.id)
                                state.save()
                            }
                        }
                    )
                }
                .onMove { source, destination in
                    state.moveOutlineItem(from: source, to: destination)
                    state.save()
                }
            }

            // Add new outline item
            HStack(spacing: 6) {
                Image(systemName: "plus.circle.fill")
                    .font(DS.callout)
                    .foregroundStyle(DS.accent.opacity(0.5))

                TextField("Add outline point...", text: $newOutlineText)
                    .textFieldStyle(.plain)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.text)
                    .onSubmit { addOutlineItem() }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.radiusSmall)
                            .stroke(DS.borderSubtle, lineWidth: 1)
                    )
            )
        }
    }

    @ViewBuilder
    private var outlineSectionHeader: some View {
        HStack(spacing: 6) {
            Text("OUTLINE")
                .font(DS.sectionLabel)
                .foregroundStyle(DS.textMuted)
                .tracking(0.88)

            if state.outline.isEmpty {
                generateOutlineButton
            }

            Spacer()

            if !state.outline.isEmpty {
                Text("\(state.completedOutlineCount)/\(state.outline.count)")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DS.accent.opacity(0.15), in: Capsule())
            }
        }
    }

    @ViewBuilder
    private var generateOutlineButton: some View {
        if isGeneratingOpusOutline {
            HStack(spacing: 4) {
                ProgressView()
                    .scaleEffect(0.5)
                    .tint(DS.accent)
                Text("Generating...")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
            }
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Button(action: generateOpusOutline) {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(DS.caption2)
                        Text("Generate")
                            .font(DS.caption2)
                    }
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)

                if let error = opusOutlineError {
                    Text(error)
                        .font(DS.caption2)
                        .foregroundStyle(.orange.opacity(0.8))
                }
            }
        }
    }

    private func generateOpusOutline() {
        isGeneratingOpusOutline = true
        opusOutlineError = nil
        Task {
            if let engine = writingEngine {
                await engine.suggestOutline()
                await MainActor.run {
                    if let error = engine.error {
                        opusOutlineError = "Failed: \(error)"
                    }
                    isGeneratingOpusOutline = false
                }
            } else {
                await MainActor.run {
                    opusOutlineError = "Engine not initialized"
                    isGeneratingOpusOutline = false
                }
            }
        }
    }

    private func addOutlineItem() {
        let trimmed = newOutlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(ProMotionSprings.snappy) {
            state.addOutlineItem(trimmed)
            newOutlineText = ""
            state.save()
        }
    }

    // MARK: - Source Idea Section

    @ViewBuilder
    private var sourceIdeaSection: some View {
        if let idea = sourceIdea {
            contextSectionHeader(title: "SOURCE IDEA", icon: "lightbulb.fill")
            sourceIdeaCard(idea)
        }
    }

    private func sourceIdeaCard(_ idea: Atom) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": idea.uuid]
            )
        } label: {
            sourceIdeaCardLabel(idea)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func sourceIdeaCardLabel(_ idea: Atom) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb.fill")
                .font(DS.footnote)
                .foregroundStyle(CosmoMentionColors.idea)

            VStack(alignment: .leading, spacing: 2) {
                Text(idea.title ?? "Untitled Idea")
                    .font(DS.caption)
                    .foregroundStyle(DS.text)
                    .lineLimit(2)

                if let body = idea.body, !body.isEmpty {
                    Text(String(body.prefix(60)))
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(1)
                }

                if let ideaMeta = idea.ideaMetadata,
                   let status = ideaMeta.ideaStatus {
                    ideaStatusBadge(status)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
    }

    private func ideaStatusBadge(_ status: IdeaStatus) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.displayName)
                .font(DS.caption2)
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.15), in: Capsule())
    }

    // MARK: - Matched Swipes Section

    @ViewBuilder
    private var matchedSwipesSection: some View {
        if !matchedSwipeAtoms.isEmpty {
            // Blueprint (first swipe — set as primary in promoteToContent)
            if let blueprint = matchedSwipeAtoms.first {
                contextSectionHeader(title: "BLUEPRINT", icon: "doc.text.magnifyingglass")
                swipeCard(blueprint)
            }

            // Supporting swipes (remaining)
            let supporting = Array(matchedSwipeAtoms.dropFirst())
            if !supporting.isEmpty {
                contextSectionHeader(title: "SUPPORTING SWIPES", icon: "doc.on.doc.fill")
                supportingSwipesContent(supporting)
            }
        }
    }

    @ViewBuilder
    private func supportingSwipesContent(_ swipes: [Atom]) -> some View {
        VStack(spacing: 4) {
            let displaySwipes = showAllSwipes ? swipes : Array(swipes.prefix(3))
            ForEach(displaySwipes, id: \.uuid) { swipe in
                swipeCard(swipe)
            }

            if swipes.count > 3 {
                Button {
                    withAnimation(ProMotionSprings.snappy) {
                        showAllSwipes.toggle()
                    }
                } label: {
                    showAllSwipesLabel
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var showAllSwipesLabel: some View {
        HStack(spacing: 4) {
            Text(showAllSwipes ? "Show less" : "Show all \(matchedSwipeAtoms.count)")
                .font(DS.caption2)
            Image(systemName: showAllSwipes ? "chevron.up" : "chevron.down")
                .font(DS.caption2)
        }
        .foregroundStyle(DS.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    private func swipeCard(_ swipe: Atom) -> some View {
        Button {
            // Open as pane (side-by-side) instead of replacing focus mode
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openAsPane,
                object: nil,
                userInfo: [
                    "type": EntityType.research,
                    "id": swipe.id ?? Int64(0)
                ]
            )
        } label: {
            swipeCardLabel(swipe)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func swipeCardLabel(_ swipe: Atom) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DS.entitySwipe)
                .frame(width: 4, height: 4)

            Text(swipe.title ?? "Untitled Swipe")
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            if let swipeAnalysis = swipe.swipeAnalysis,
               let hookType = swipeAnalysis.hookType {
                Text(hookType.displayName)
                    .font(DS.caption2)
                    .foregroundStyle(DS.entitySwipe)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DS.entitySwipe.opacity(0.12), in: Capsule())
            }

            Image(systemName: "rectangle.split.2x1")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    // MARK: - Inherited Connections Section

    @ViewBuilder
    private var inheritedConnectionsSection: some View {
        if !inheritedConnectionAtoms.isEmpty {
            contextSectionHeader(title: "CONNECTIONS", icon: "link.circle.fill")
            connectionsContent
        }
    }

    @ViewBuilder
    private var connectionsContent: some View {
        VStack(spacing: 4) {
            ForEach(inheritedConnectionAtoms.prefix(3), id: \.uuid) { conn in
                connectionCard(conn)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
    }

    private func connectionCard(_ conn: Atom) -> some View {
        let maturity = conn.connectionMaturityLevel ?? "emerging"
        return Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": conn.uuid]
            )
        } label: {
            connectionCardLabel(conn, maturity: maturity)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func connectionCardLabel(_ conn: Atom, maturity: String) -> some View {
        HStack(spacing: 6) {
            Text(conn.title ?? "Connection")
                .font(DS.caption)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            connectionMaturityBadge(maturity)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private func connectionMaturityBadge(_ maturity: String) -> some View {
        let color: Color = {
            switch maturity.lowercased() {
            case "mature", "deep": return DS.green
            case "developing": return DS.info
            case "emerging": return DS.orange
            default: return DS.textSecondary
            }
        }()

        Text(maturity.capitalized)
            .font(DS.caption2)
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Framework Section

    @ViewBuilder
    private var frameworkSection: some View {
        if let framework = selectedFramework, !framework.isEmpty {
            contextSectionHeader(title: "FRAMEWORK", icon: "rectangle.3.group.fill")

            Text(framework)
                .font(DS.caption)
                .foregroundStyle(accentColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(accentColor.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Inherited Hooks Section (from context, read-only)

    @ViewBuilder
    private var inheritedHooksSection: some View {
        if !inheritedHooks.isEmpty {
            contextSectionHeader(title: "CONTEXT HOOKS", icon: "text.quote")
            inheritedHooksContent
        }
    }

    @ViewBuilder
    private var inheritedHooksContent: some View {
        VStack(spacing: 6) {
            ForEach(Array(inheritedHooks.enumerated()), id: \.offset) { index, hook in
                inheritedHookCard(hook, index: index)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
    }

    private func inheritedHookCard(_ hook: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1)")
                .font(DS.caption2)
                .foregroundStyle(accentColor)
                .frame(width: 14)

            Text(hook)
                .font(DS.caption2)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(3)

            Spacer(minLength: 2)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hook, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 20, height: 20)
                    .background(DS.surface, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Codex Panels

    @ViewBuilder
    private var codexOutlinePanel: some View {
        if let outline = state.codexOutline, !outline.slides.isEmpty {
            ContentSidebarPanel(
                title: "Codex Outline",
                icon: "list.bullet.rectangle",
                accentColor: DS.accent,
                badge: outline.slides.count,
                isExpanded: $state.outlinePanelExpanded
            ) {
                if let arc = outline.arcShape {
                    HStack(spacing: 6) {
                        Text("Arc:")
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                        CodexConceptTag(
                            name: arc,
                            color: CodexElementCategory.arcShape.color
                        )
                    }
                    .padding(.bottom, 4)
                }

                ForEach(outline.slides) { slide in
                    codexOutlineSlideRow(slide)
                }
            }
        }
    }

    private func codexOutlineSlideRow(_ slide: CodexOutlineSlide) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Slide \(slide.position)")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.textOnAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DS.accent, in: Capsule())

            FlowLayout(spacing: 3) {
                if let sa = slide.speechAct {
                    CodexConceptTag(
                        name: sa,
                        color: CodexElementCategory.speechAct.color
                    )
                }
                ForEach(slide.readerDeltas, id: \.self) { delta in
                    CodexConceptTag(
                        name: delta,
                        color: CodexElementCategory.readerDelta.color
                    )
                }
                if let frame = slide.frame {
                    CodexConceptTag(
                        name: frame,
                        color: CodexElementCategory.frame.color
                    )
                }
                ForEach(slide.techniques, id: \.self) { tech in
                    CodexConceptTag(
                        name: tech,
                        color: CodexElementCategory.technique.color
                    )
                }
                if let transition = slide.transition {
                    CodexConceptTag(
                        name: "→ \(transition)",
                        color: CodexElementCategory.transition.color
                    )
                }
            }

            if let note = slide.note, !note.isEmpty {
                Text(note)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .italic()
            }
        }
        .padding(8)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusXSmall))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusXSmall)
                .stroke(DS.borderSubtle, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var codexResearchPanel: some View {
        if let results = state.inheritedResearchResults, !results.isEmpty {
            ContentSidebarPanel(
                title: "Research",
                icon: "magnifyingglass",
                accentColor: DS.green,
                badge: results.count,
                isExpanded: $state.researchPanelExpanded
            ) {
                ForEach(results) { result in
                    sidebarResearchCard(result)
                }
            }
        }
    }

    private func sidebarResearchCard(_ result: IdeaResearchResult) -> some View {
        ExpandableResearchCard(result: result)
    }

    @ViewBuilder
    private var codexArcPanel: some View {
        if let arcRecs = state.inheritedArcRecommendations, !arcRecs.isEmpty {
            ContentSidebarPanel(
                title: "Arc & Recommendations",
                icon: "waveform.path.ecg",
                accentColor: CodexElementCategory.arcShape.color,
                isExpanded: $state.arcPanelExpanded
            ) {
                ForEach(arcRecs) { rec in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            CodexConceptTag(
                                name: rec.arcName,
                                color: CodexElementCategory.arcShape.color
                            )
                            Text(String(format: "%.0f%%", rec.confidence * 100))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.textMuted)
                        }
                        Text(rec.explanation)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusXSmall))
                }
            }
        }
    }

    @ViewBuilder
    private var codexContextDirectionPanel: some View {
        let hasContext = !state.inheritedIdeaContext.isEmpty
        let hasDirection = !state.inheritedCreativeDirection.isEmpty
        if hasContext || hasDirection {
            ContentSidebarPanel(
                title: "Context & Direction",
                icon: "text.alignleft",
                accentColor: DS.info,
                isExpanded: $state.contextPanelExpanded
            ) {
                if hasContext {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("IDEA CONTEXT")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(DS.textMuted)
                        Text(state.inheritedIdeaContext)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textSecondary)
                            .lineSpacing(2)
                    }
                }
                if hasDirection {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("CREATIVE DIRECTION")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(DS.textMuted)
                        Text(state.inheritedCreativeDirection)
                            .font(DS.caption2)
                            .foregroundStyle(DS.textSecondary)
                            .lineSpacing(2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var codexChatHistoryPanel: some View {
        if let messages = state.inheritedChatHistory, !messages.isEmpty {
            ContentSidebarPanel(
                title: "Brainstorm Chat",
                icon: "bubble.left.and.bubble.right",
                accentColor: DS.entityIdea,
                badge: messages.count,
                isExpanded: $state.chatPanelExpanded
            ) {
                ForEach(messages) { msg in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: msg.role == "user" ? "person.fill" : "sparkles")
                            .font(.system(size: 8))
                            .foregroundStyle(
                                msg.role == "user" ? DS.textMuted : DS.accent
                            )
                            .frame(width: 14)
                            .padding(.top, 2)

                        Text(msg.content)
                            .font(DS.caption2)
                            .foregroundStyle(
                                msg.role == "user" ? DS.textSecondary : DS.text
                            )
                            .lineLimit(4)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var codexQuickRefPanel: some View {
        if !state.codexElementNames.isEmpty {
            ContentSidebarPanel(
                title: "Codex Elements",
                icon: "atom",
                accentColor: DS.accent,
                badge: state.codexElementNames.count,
                isExpanded: $state.codexRefPanelExpanded
            ) {
                FlowLayout(spacing: 4) {
                    ForEach(state.codexElementNames, id: \.self) { name in
                        CodexConceptTag(name: name, color: DS.accent)
                    }
                }
            }
        }
    }

    // MARK: - Intelligence Section (Collapsible)

    @ViewBuilder
    private var intelligenceSection: some View {
        if hasIntelligenceData || isLoadingMetaPattern || isLoadingRelated {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    showIntelligence.toggle()
                }
            } label: {
                intelligenceHeaderLabel
            }
            .buttonStyle(.plain)

            if showIntelligence {
                intelligenceContent
            }
        }
    }

    @ViewBuilder
    private var intelligenceHeaderLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: showIntelligence ? "chevron.down" : "chevron.right")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 10)

            Image(systemName: "brain.head.profile")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)

            Text("INTELLIGENCE")
                .font(DS.caption2)
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)

            Spacer()

            let count = intelligenceItemCount
            if count > 0 {
                Text("\(count)")
                    .font(DS.caption2)
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
        }
    }

    private var intelligenceItemCount: Int {
        var count = 0
        if metaPatternReport != nil { count += 1 }
        if hasDraftIntelligence { count += 1 }
        count += relatedContent.count
        count += ambientEngine.ambientResults.count
        return count
    }

    @ViewBuilder
    private var intelligenceContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            whatsWorkingSubsection
            draftIntelligenceSubsection
            relatedContentSubsection
            ambientKnowledgeSubsection
        }
    }

    // MARK: - What's Working Subsection

    @ViewBuilder
    private var whatsWorkingSubsection: some View {
        if let report = metaPatternReport {
            whatsWorkingContent(report)
        } else if isLoadingMetaPattern {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Analyzing patterns...")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func whatsWorkingContent(_ report: MetaPatternReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
                Text("WHAT'S WORKING")
                    .font(DS.caption2)
                    .tracking(0.8)
                    .foregroundStyle(DS.textMuted)
            }

            whatsWorkingScopeRow(report)

            if let topHook = report.dominantHooks.first {
                whatsWorkingHookRow(topHook)
            }

            if let topFw = report.winningStructures.first {
                whatsWorkingFrameworkRow(topFw)
            }

            if !report.trendingTopics.isEmpty {
                whatsWorkingTrendingRow(report.trendingTopics)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.green.opacity(0.2), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func whatsWorkingScopeRow(_ report: MetaPatternReport) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkle")
                .font(DS.caption2)
                .foregroundStyle(DS.green)
            Text("\(report.platform.capitalized) \(report.format) — \(report.niche)")
                .font(DS.caption2)
                .foregroundStyle(DS.green)
                .lineLimit(1)
            Spacer()
            Text("\(report.sampleSize)")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    @ViewBuilder
    private func whatsWorkingHookRow(_ topHook: HookPattern) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "text.quote")
                .font(DS.caption2)
                .foregroundStyle(DS.entityIdea)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(topHook.hookType)
                    .font(DS.caption2)
                    .foregroundStyle(DS.text)
                Text("\(String(format: "%.0f", topHook.frequency * 100))% of top content")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private func whatsWorkingFrameworkRow(_ topFw: StructurePattern) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.3.group.fill")
                .font(DS.caption2)
                .foregroundStyle(DS.orange)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(topFw.framework)
                    .font(DS.caption2)
                    .foregroundStyle(DS.text)
                Text("\(String(format: "%.0f", topFw.frequency * 100))% adoption")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
        }
    }

    @ViewBuilder
    private func whatsWorkingTrendingRow(_ topics: [String]) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.up.right")
                .font(DS.caption2)
                .foregroundStyle(DS.green)
                .frame(width: 14)
            ForEach(topics.prefix(3), id: \.self) { item in
                Text(item)
                    .font(DS.caption2)
                    .foregroundStyle(DS.green)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(DS.green.opacity(0.12), in: Capsule())
            }
        }
    }

    // MARK: - Draft Intelligence Subsection

    @ViewBuilder
    private var draftIntelligenceSubsection: some View {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        let swipeUUIDs = metadata?.inheritedSwipeUUIDs ?? []

        if !swipeUUIDs.isEmpty {
            draftIntelligenceContent(metadata: metadata, swipeUUIDs: swipeUUIDs)
        }
    }

    @ViewBuilder
    private func draftIntelligenceContent(metadata: ContentAtomMetadata?, swipeUUIDs: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                Text("DRAFT INTELLIGENCE")
                    .font(DS.caption2)
                    .tracking(0.8)
                    .foregroundStyle(DS.textMuted)
            }

            HStack(spacing: 6) {
                Image(systemName: "doc.on.doc.fill")
                    .font(DS.caption2)
                    .foregroundStyle(DS.entitySwipe)
                Text("\(swipeUUIDs.count) matched swipe\(swipeUUIDs.count == 1 ? "" : "s")")
                    .font(DS.caption)
                    .foregroundStyle(DS.textSecondary)
            }

            if let draftPackageData = atom.structured,
               let data = draftPackageData.data(using: .utf8),
               let draftPackage = try? JSONDecoder().decode(ContentDraftPackage.self, from: data) {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.fill")
                        .font(DS.caption2)
                        .foregroundStyle(DS.accent)
                    Text("Confidence: \(String(format: "%.0f%%", draftPackage.confidence * 100))")
                        .font(DS.caption)
                        .foregroundStyle(DS.textSecondary)
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.accent.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Related Content Subsection

    @ViewBuilder
    private var relatedContentSubsection: some View {
        if isLoadingRelated {
            HStack(spacing: 6) {
                ProgressView()
                    .controlSize(.mini)
                Text("Finding related...")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(8)
        } else if !relatedContent.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                    Text("RELATED")
                        .font(DS.caption2)
                        .tracking(0.8)
                        .foregroundStyle(DS.textMuted)
                }

                VStack(spacing: 3) {
                    ForEach(relatedContent.prefix(6)) { ref in
                        relatedContentCard(ref)
                    }
                }
            }
        }
    }

    private func relatedContentCard(_ ref: RelatedAtomRef) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": ref.atomUUID]
            )
        } label: {
            relatedContentCardLabel(ref)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func relatedContentCardLabel(_ ref: RelatedAtomRef) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(ref.tier.accentColor)
                .frame(width: 2, height: 24)

            Image(systemName: iconForAtomType(ref.type))
                .font(DS.caption2)
                .foregroundStyle(colorForAtomType(ref.type))
                .frame(width: 12)

            Text(ref.title)
                .font(DS.caption2)
                .foregroundStyle(DS.text)
                .lineLimit(1)

            Spacer()

            Text(String(format: "%.0f%%", ref.relevanceScore * 100))
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
                        .stroke(DS.border, lineWidth: 1)
                )
        )
    }

    // MARK: - Ambient Knowledge Subsection

    @ViewBuilder
    private var ambientKnowledgeSubsection: some View {
        if !ambientEngine.ambientResults.isEmpty || ambientEngine.isLoading {
            VStack(alignment: .leading, spacing: 6) {
                ambientHeaderRow

                if ambientEngine.isLoading {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(DS.accent)
                        Text("Searching...")
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                } else {
                    ForEach(ambientEngine.ambientResults.prefix(5)) { result in
                        AmbientResultCard(
                            result: result,
                            onPull: {
                                ambientEngine.pullToCanvas(result: result, sourceBlockUUID: atom.uuid)
                            },
                            onDismiss: {
                                withAnimation(ProMotionSprings.snappy) {
                                    ambientEngine.dismiss(uuid: result.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var ambientHeaderRow: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(DS.caption2)
                .foregroundStyle(DS.accent)
            Text("AMBIENT")
                .font(DS.caption2)
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)

            Spacer()

            if !ambientEngine.ambientResults.isEmpty {
                Text("\(ambientEngine.ambientResults.count)")
                    .font(DS.caption2)
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(DS.accent.opacity(0.15), in: Capsule())
            }
        }
    }

    // MARK: - Context Section Header

    private func contextSectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
            Text(title)
                .font(DS.caption2)
                .tracking(0.8)
                .foregroundStyle(DS.textMuted)
        }
    }

    // MARK: - Data Loading (ported from ContentContextPanel)

    private func loadInheritedContext() async {
        guard let metadata = atom.metadataValue(as: ContentAtomMetadata.self) else {
            isLoadingContext = false
            return
        }

        // Load source idea
        if let ideaUUID = metadata.sourceIdeaUUID {
            sourceIdea = try? await AtomRepository.shared.fetch(uuid: ideaUUID)
        }

        // Load matched swipes
        if let swipeUUIDs = metadata.inheritedSwipeUUIDs {
            for uuid in swipeUUIDs.prefix(5) {
                if let swipe = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    matchedSwipeAtoms.append(swipe)
                }
            }
        }

        // Load inherited connections
        if let connectionUUIDs = metadata.inheritedConnectionIds {
            for uuid in connectionUUIDs.prefix(5) {
                if let conn = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    inheritedConnectionAtoms.append(conn)
                }
            }
        }

        selectedFramework = metadata.inheritedFramework
        inheritedHooks = metadata.inheritedHooks ?? []

        isLoadingContext = false

        // Load meta-pattern report
        await loadMetaPattern()

        // Search related content
        await refreshRelatedContent()
    }

    private func loadMetaPattern() async {
        isLoadingMetaPattern = true
        defer { isLoadingMetaPattern = false }
        metaPatternReport = await MetaPatternEngine.shared.getRelevantReport(for: atom)
    }

    private func refreshRelatedContent() async {
        let query = atom.title ?? ""
        guard !query.isEmpty else { return }
        isLoadingRelated = true
        defer { isLoadingRelated = false }

        var allRefs: [RelatedAtomRef] = []
        var seenUUIDs: Set<String> = [atom.uuid]

        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        var niche: String?
        if let clientUUID = metadata?.clientProfileUUID,
           let client = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = client.metadataValue(as: ClientProfileMetadata.self) {
            niche = clientMeta.niche
        }

        // Primary tier: Same format research swipes
        do {
            let primaryQuery = [query, niche].compactMap { $0 }.joined(separator: " ")
            let primaryResults = try await HybridSearchEngine.shared.search(
                query: primaryQuery,
                limit: 6,
                entityTypes: [.research]
            )
            for result in primaryResults where !(seenUUIDs.contains(result.entityUUID ?? "")) {
                guard allRefs.filter({ $0.tier == .primary }).count < 3 else { break }
                let uuid = result.entityUUID ?? ""
                seenUUIDs.insert(uuid)
                allRefs.append(RelatedAtomRef(
                    atomUUID: uuid,
                    title: result.title,
                    type: AtomType(rawValue: result.entityType.rawValue) ?? .research,
                    relevanceScore: result.combinedScore,
                    preview: result.preview,
                    tier: .primary
                ))
            }
        } catch {
            print("ContentSidebar: primary tier search failed: \(error)")
        }

        // Secondary tier: Same niche content atoms
        do {
            let secondaryQuery = niche ?? query
            let secondaryResults = try await HybridSearchEngine.shared.search(
                query: secondaryQuery,
                limit: 6,
                entityTypes: [.content]
            )
            for result in secondaryResults where !(seenUUIDs.contains(result.entityUUID ?? "")) {
                guard allRefs.filter({ $0.tier == .secondary }).count < 3 else { break }
                let uuid = result.entityUUID ?? ""
                seenUUIDs.insert(uuid)
                allRefs.append(RelatedAtomRef(
                    atomUUID: uuid,
                    title: result.title,
                    type: AtomType(rawValue: result.entityType.rawValue) ?? .content,
                    relevanceScore: result.combinedScore,
                    preview: result.preview,
                    tier: .secondary
                ))
            }
        } catch {
            print("ContentSidebar: secondary tier search failed: \(error)")
        }

        // Tertiary tier: Broad semantic search
        do {
            let tertiaryResults = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 8
            )
            for result in tertiaryResults where !(seenUUIDs.contains(result.entityUUID ?? "")) {
                guard allRefs.filter({ $0.tier == .tertiary }).count < 4 else { break }
                let uuid = result.entityUUID ?? ""
                seenUUIDs.insert(uuid)
                allRefs.append(RelatedAtomRef(
                    atomUUID: uuid,
                    title: result.title,
                    type: AtomType(rawValue: result.entityType.rawValue) ?? .idea,
                    relevanceScore: result.combinedScore,
                    preview: result.preview,
                    tier: .tertiary
                ))
            }
        } catch {
            print("ContentSidebar: tertiary tier search failed: \(error)")
        }

        relatedContent = allRefs
    }

    // MARK: - Helpers

    private func iconForAtomType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .content: return "doc.text.fill"
        case .research: return "magnifyingglass"
        case .connection: return "link"
        case .task: return "checkmark.circle.fill"
        case .note: return "note.text"
        default: return "doc.fill"
        }
    }

    private func colorForAtomType(_ type: AtomType) -> Color {
        switch type {
        case .idea: return CosmoMentionColors.idea
        case .content: return CosmoMentionColors.content
        case .research: return CosmoMentionColors.research
        case .connection: return CosmoMentionColors.connection
        case .task: return CosmoMentionColors.task
        case .note: return CosmoMentionColors.note
        default: return CosmoMentionColors.defaultColor
        }
    }
}

// MARK: - Sidebar Hook Row

private struct SidebarHookRow: View {
    let hook: String
    let index: Int
    let onUpdate: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editText = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(index + 1).")
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
                .frame(width: 16, alignment: .trailing)
                .padding(.top, isEditing ? 4 : 0)

            if isEditing {
                MultilineHookEditor(
                    text: $editText,
                    isFocused: $isFocused,
                    fontSize: 12,
                    onCommit: { commitEdit() }
                )
            } else {
                Text(hook)
                    .font(DS.buttonText)
                    .foregroundStyle(DS.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .onTapGesture(count: 2) {
                        editText = hook
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: DS.radiusSmall)
                .fill(DS.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall)
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

// MARK: - Sidebar Outline Row

private struct SidebarOutlineRow: View {
    let item: OutlineItem
    let onToggle: () -> Void
    let onUpdateTitle: (String) -> Void
    let onDelete: () -> Void

    @State private var isEditing = false
    @State private var editTitle = ""
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            // Checkbox
            Button(action: onToggle) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(DS.callout)
                    .foregroundStyle(item.isCompleted ? DS.accent : DS.textMuted)
            }
            .buttonStyle(.plain)

            // Title
            if isEditing {
                TextField("", text: $editTitle)
                    .textFieldStyle(.plain)
                    .font(DS.subheadline)
                    .foregroundStyle(DS.text)
                    .focused($isFocused)
                    .onSubmit { commitEdit() }
                    .onChange(of: isFocused) { _, focused in
                        if !focused { commitEdit() }
                    }
            } else {
                Text(item.title)
                    .font(DS.subheadline)
                    .foregroundStyle(item.isCompleted ? DS.textMuted : DS.textSecondary)
                    .strikethrough(item.isCompleted, color: DS.textMuted)
                    .lineLimit(2)
                    .onTapGesture(count: 2) {
                        editTitle = item.title
                        isEditing = true
                        isFocused = true
                    }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(DS.caption2)
                        .foregroundStyle(DS.textMuted)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
    }

    private func commitEdit() {
        let trimmed = editTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { onUpdateTitle(trimmed) }
        isEditing = false
    }
}

// MARK: - FlowLayout (wrapping horizontal layout)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews)
        -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0
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
            maxX = max(maxX, currentX - spacing)
        }
        return (positions, CGSize(width: maxX, height: currentY + lineHeight))
    }
}

// MARK: - Expandable Research Card

private struct ExpandableResearchCard: View {
    let result: IdeaResearchResult
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(result.title)
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.text)
                .lineLimit(isExpanded ? nil : 2)

            Text(result.snippet)
                .font(DS.caption2)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(isExpanded ? nil : 3)

            if isExpanded, let url = result.url, !url.isEmpty {
                Text(url)
                    .font(.system(size: 9))
                    .foregroundStyle(DS.info)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                if !result.source.isEmpty {
                    Text(result.source)
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                }
                if let proof = result.proofType {
                    CodexConceptTag(
                        name: proof,
                        color: CodexElementCategory.proofType.color
                    )
                }
            }
        }
        .padding(8)
        .background(DS.surfaceElevated, in: .rect(cornerRadius: DS.radiusXSmall))
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(ProMotionSprings.snappy) {
                isExpanded.toggle()
            }
        }
    }
}
