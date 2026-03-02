// CosmoOS/UI/FocusMode/Content/ContentContextPanel.swift
// Collapsible right sidebar showing inherited idea context for Content Focus Mode
// February 2026 — Redesigned to hide empty sections and match polish sidebar quality

import SwiftUI

// MARK: - Content Context Panel

/// Collapsible right sidebar that shows the inherited context chain:
/// Source Idea → Matched Swipes → Framework → Hooks → Intelligence
/// Only sections with data are displayed — no "No X found" empty states.
struct ContentContextPanel: View {
    let atom: Atom
    @Binding var state: ContentFocusModeState
    let isVisible: Bool

    @State private var sourceIdea: Atom?
    @State private var matchedSwipeAtoms: [Atom] = []
    @State private var inheritedConnectionAtoms: [Atom] = []
    @State private var selectedFramework: String?
    @State private var hooks: [String] = []
    @State private var relatedContent: [RelatedAtomRef] = []
    @State private var isLoadingRelated = false
    @State private var relatedSearchTask: Task<Void, Never>?
    @State private var isGeneratingDraft = false
    @State private var metaPatternReport: MetaPatternReport?
    @State private var isLoadingMetaPattern = false
    @StateObject private var ambientEngine = AmbientFieldEngine()
    @State private var showAllSwipes = false
    @State private var showIntelligence = false
    @State private var isLoading = true

    private let panelWidth: CGFloat = 320
    private let accentColor = CosmoMentionColors.content // Blue

    /// Whether any content section has data to display.
    /// When false, the panel collapses to zero width to give more space to the editor.
    private var hasAnyContent: Bool {
        sourceIdea != nil
        || !matchedSwipeAtoms.isEmpty
        || !inheritedConnectionAtoms.isEmpty
        || (selectedFramework != nil && !selectedFramework!.isEmpty)
        || !hooks.isEmpty
        || hasIntelligenceData
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

    var body: some View {
        if isVisible && (isLoading || hasAnyContent) {
            VStack(spacing: 0) {
                panelHeader

                Divider().background(DS.border)

                if isLoading {
                    loadingState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            sourceIdeaSection
                            matchedSwipesSection
                            inheritedConnectionsSection
                            frameworkSection
                            hooksSection
                            intelligenceSection
                        }
                        .padding(16)
                    }
                }
            }
            .frame(width: panelWidth)
            .background(DS.surface)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(DS.border)
                    .frame(width: 1)
            }
            .onAppear {
                Task {
                    await loadInheritedContext()
                    isLoading = false
                }
                let queryText = [atom.title ?? "", String((atom.body ?? "").prefix(200))].joined(separator: " ")
                ambientEngine.updateContext(focusAtomUUID: atom.uuid, currentText: queryText)
            }
            .onChange(of: state.draftContent) { _ in
                debounceRelatedRefresh()
            }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 14))
                .foregroundColor(accentColor)

            Text("Context")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(DS.text)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Loading State

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
                .tint(DS.textMuted)
            Text("Loading context...")
                .font(.system(size: 11))
                .foregroundColor(DS.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "text.below.photo")
                .font(.system(size: 28, weight: .light))
                .foregroundColor(DS.textMuted.opacity(0.5))

            VStack(spacing: 4) {
                Text("Start writing to build context")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(DS.textMuted)

                Text("Context from linked ideas, swipes,\nand research will appear here")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Source Idea Section

    @ViewBuilder
    private var sourceIdeaSection: some View {
        if let idea = sourceIdea {
            sectionHeader(title: "SOURCE IDEA", icon: "lightbulb.fill")
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
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 12))
                    .foregroundColor(CosmoMentionColors.idea)

                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.title ?? "Untitled Idea")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.text)
                        .lineLimit(2)

                    if let body = idea.body, !body.isEmpty {
                        Text(String(body.prefix(80)))
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                            .lineLimit(2)
                    }

                    if let ideaMeta = idea.ideaMetadata,
                       let status = ideaMeta.ideaStatus {
                        ideaStatusBadge(status)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(DS.textMuted)
            }
            .padding(12)
            .dsGlassSection()
        }
        .buttonStyle(.plain)
    }

    private func ideaStatusBadge(_ status: IdeaStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(status.color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(status.color.opacity(0.15), in: Capsule())
    }

    // MARK: - Matched Swipes Section

    @ViewBuilder
    private var matchedSwipesSection: some View {
        if !matchedSwipeAtoms.isEmpty {
            sectionHeader(title: "MATCHED SWIPES", icon: "doc.on.doc.fill")

            VStack(spacing: 6) {
                let displaySwipes = showAllSwipes ? matchedSwipeAtoms : Array(matchedSwipeAtoms.prefix(3))
                ForEach(displaySwipes, id: \.uuid) { swipe in
                    swipeCard(swipe)
                }

                if matchedSwipeAtoms.count > 3 {
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
            .padding(12)
            .dsGlassSection()
        }
    }

    @ViewBuilder
    private var showAllSwipesLabel: some View {
        HStack(spacing: 4) {
            Text(showAllSwipes ? "Show less" : "Show all \(matchedSwipeAtoms.count)")
                .font(.system(size: 9, weight: .medium))
            Image(systemName: showAllSwipes ? "chevron.up" : "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundColor(DS.textMuted)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func swipeCard(_ swipe: Atom) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": swipe.uuid]
            )
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(DS.entitySwipe)
                    .frame(width: 5, height: 5)

                Text(swipe.title ?? "Untitled Swipe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                // Hook type badge if available
                if let swipeAnalysis = swipe.swipeAnalysis,
                   let hookType = swipeAnalysis.hookType {
                    Text(hookType.displayName)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(DS.entitySwipe)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DS.entitySwipe.opacity(0.12), in: Capsule())
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Inherited Connections Section

    @ViewBuilder
    private var inheritedConnectionsSection: some View {
        if !inheritedConnectionAtoms.isEmpty {
            sectionHeader(title: "CONNECTIONS", icon: "link.circle.fill")

            VStack(spacing: 6) {
                ForEach(inheritedConnectionAtoms.prefix(3), id: \.uuid) { conn in
                    inheritedConnectionCard(conn)
                }
            }
            .padding(12)
            .dsGlassSection()
        }
    }

    @ViewBuilder
    private func inheritedConnectionCard(_ conn: Atom) -> some View {
        let maturity = conn.connectionMaturityLevel ?? "emerging"

        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": conn.uuid]
            )
        } label: {
            HStack(spacing: 8) {
                Text(conn.title ?? "Connection")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                inheritedConnectionMaturityBadge(maturity)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func inheritedConnectionMaturityBadge(_ maturity: String) -> some View {
        let color: Color = {
            switch maturity.lowercased() {
            case "mature", "deep": return Color(hex: "22C55E")
            case "developing": return Color(hex: "3B82F6")
            case "emerging": return Color(hex: "FBBF24")
            default: return Color(hex: "64748B")
            }
        }()

        Text(maturity.capitalized)
            .font(.system(size: 9, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Framework Section

    @ViewBuilder
    private var frameworkSection: some View {
        if let framework = selectedFramework, !framework.isEmpty {
            sectionHeader(title: "FRAMEWORK", icon: "rectangle.3.group.fill")

            Text(framework)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(accentColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(accentColor.opacity(0.12), in: Capsule())
        }
    }

    // MARK: - Hooks Section

    @ViewBuilder
    private var hooksSection: some View {
        if !hooks.isEmpty {
            sectionHeader(title: "HOOKS", icon: "text.quote")

            VStack(spacing: 8) {
                ForEach(Array(hooks.enumerated()), id: \.offset) { index, hook in
                    hookCard(hook, index: index)
                }
            }
            .padding(12)
            .dsGlassSection()
        }
    }

    private func hookCard(_ hook: String, index: Int) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(accentColor)
                .frame(width: 16)

            Text(hook)
                .font(.system(size: 11))
                .foregroundColor(DS.textSecondary)
                .lineLimit(3)

            Spacer(minLength: 4)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hook, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 9))
                    .foregroundColor(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(DS.glassCardFill, in: Circle())
            }
            .buttonStyle(.plain)
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
                VStack(alignment: .leading, spacing: 16) {
                    whatsWorkingSubsection
                    draftIntelligenceSubsection
                    relatedContentSubsection
                    ambientKnowledgeSubsection
                }
            }
        }
    }

    @ViewBuilder
    private var intelligenceHeaderLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: showIntelligence ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(DS.textMuted)
                .frame(width: 12)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)

            Text("INTELLIGENCE")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(DS.textMuted)

            Spacer()

            let count = intelligenceItemCount
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor)
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

    // MARK: - What's Working Subsection

    @ViewBuilder
    private var whatsWorkingSubsection: some View {
        if let report = metaPatternReport {
            whatsWorkingContent(report)
        } else if isLoadingMetaPattern {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing patterns...")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
            .padding(10)
        }
    }

    @ViewBuilder
    private func whatsWorkingContent(_ report: MetaPatternReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Scope badge
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#34D399"))
                Text("WHAT'S WORKING")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(DS.textMuted)
            }

            HStack(spacing: 6) {
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundColor(Color(hex: "#34D399"))
                Text("\(report.platform.capitalized) \(report.format) — \(report.niche)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(hex: "#34D399"))
                Spacer()
                Text("\(report.sampleSize) swipes")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }

            if let topHook = report.dominantHooks.first {
                HStack(spacing: 8) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 10))
                        .foregroundColor(DS.entityIdea)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topHook.hookType)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.text)
                        Text("\(String(format: "%.0f", topHook.frequency * 100))% of top content")
                            .font(.system(size: 9))
                            .foregroundColor(DS.textMuted)
                    }
                }
            }

            if let topFw = report.winningStructures.first {
                HStack(spacing: 8) {
                    Image(systemName: "rectangle.3.group.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#FBBF24"))
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(topFw.framework)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(DS.text)
                        Text("\(String(format: "%.0f", topFw.frequency * 100))% adoption")
                            .font(.system(size: 9))
                            .foregroundColor(DS.textMuted)
                    }
                }
            }

            if !report.trendingTopics.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(Color(hex: "#34D399"))
                        .frame(width: 16)
                    ForEach(report.trendingTopics.prefix(3), id: \.self) { item in
                        Text(item)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(Color(hex: "#34D399"))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(hex: "#34D399").opacity(0.12), in: Capsule())
                    }
                }
            }
        }
        .padding(12)
        .dsGlassSection()
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#34D399").opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Draft Intelligence Subsection

    @ViewBuilder
    private var draftIntelligenceSubsection: some View {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        let swipeUUIDs = metadata?.inheritedSwipeUUIDs ?? []

        if !swipeUUIDs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                    Text("DRAFT INTELLIGENCE")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(DS.textMuted)
                }

                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 11))
                        .foregroundColor(DS.entitySwipe)
                    Text("\(swipeUUIDs.count) matched swipe\(swipeUUIDs.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DS.textSecondary)
                }

                if let draftPackageData = atom.structured,
                   let data = draftPackageData.data(using: .utf8),
                   let draftPackage = try? JSONDecoder().decode(ContentDraftPackage.self, from: data) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11))
                            .foregroundColor(DS.accent)
                        Text("Confidence: \(String(format: "%.0f%%", draftPackage.confidence * 100))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(DS.textSecondary)
                    }
                }

                if metadata?.draftReady == true && state.draftContent.isEmpty {
                    Button(action: { generateDraftFromPanel() }) {
                        if isGeneratingDraft {
                            draftGeneratingLabel
                        } else {
                            draftButtonContent
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingDraft)
                }
            }
            .padding(12)
            .dsGlassSection()
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.accent.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var draftGeneratingLabel: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.6)
                .tint(DS.text)
            Text("Generating...")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundColor(DS.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DS.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var draftButtonContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
            Text("Generate Draft")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(DS.text)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DS.accent, in: RoundedRectangle(cornerRadius: 8))
    }

    private func generateDraftFromPanel() {
        isGeneratingDraft = true
        Task {
            let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
            let swipeUUIDs = metadata?.inheritedSwipeUUIDs ?? []

            var ideaAtom: Atom?
            if let ideaUUID = metadata?.sourceIdeaUUID {
                ideaAtom = try? await AtomRepository.shared.fetch(uuid: ideaUUID)
            }

            var swipeAtoms: [Atom] = []
            for uuid in swipeUUIDs.prefix(5) {
                if let swipe = try? await AtomRepository.shared.fetch(uuid: uuid) {
                    swipeAtoms.append(swipe)
                }
            }

            let format: ContentFormat = .post
            var clientProfile: Atom?
            if let clientUUID = metadata?.clientProfileUUID {
                clientProfile = try? await AtomRepository.shared.fetch(uuid: clientUUID)
            }

            let sourceAtom = ideaAtom ?? atom
            guard let draftPackage = await SwipeDraftEngine.shared.generateDraftPackage(
                idea: sourceAtom,
                targetFormat: format,
                matchingSwipes: swipeAtoms,
                clientProfile: clientProfile
            ) else {
                isGeneratingDraft = false
                return
            }

            let firstDraft = await SwipeDraftEngine.shared.generateFirstDraft(
                idea: sourceAtom,
                draftPackage: draftPackage,
                targetFormat: format
            )

            await MainActor.run {
                if let draft = firstDraft, !draft.isEmpty {
                    state.draftContent = draft
                }
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
            }
        }
    }

    // MARK: - Related Content Subsection

    @ViewBuilder
    private var relatedContentSubsection: some View {
        if isLoadingRelated {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Finding related...")
                    .font(.system(size: 10))
                    .foregroundColor(DS.textMuted)
            }
            .padding(10)
        } else if !relatedContent.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "link")
                        .font(.system(size: 9))
                        .foregroundColor(DS.textMuted)
                    Text("RELATED")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(DS.textMuted)
                }

                VStack(spacing: 4) {
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
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(ref.tier.accentColor)
                    .frame(width: 2, height: 28)

                Image(systemName: iconForAtomType(ref.type))
                    .font(.system(size: 10))
                    .foregroundColor(colorForAtomType(ref.type))
                    .frame(width: 14)

                Text(ref.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(DS.text)
                    .lineLimit(1)

                Spacer()

                Text(String(format: "%.0f%%", ref.relevanceScore * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(DS.textMuted)
            }
            .padding(8)
            .dsGlassSection(cornerRadius: 8)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Ambient Knowledge Subsection

    @ViewBuilder
    private var ambientKnowledgeSubsection: some View {
        if !ambientEngine.ambientResults.isEmpty || ambientEngine.isLoading {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 9))
                        .foregroundColor(DS.accent)
                    Text("AMBIENT")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(0.8)
                        .foregroundColor(DS.textMuted)

                    Spacer()

                    if !ambientEngine.ambientResults.isEmpty {
                        Text("\(ambientEngine.ambientResults.count)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(DS.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(DS.accent.opacity(0.15), in: Capsule())
                    }
                }

                if ambientEngine.isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DS.accent)
                        Text("Searching...")
                            .font(.system(size: 10))
                            .foregroundColor(DS.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(DS.textMuted)
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(DS.textMuted)
        }
    }

    // MARK: - Data Loading

    private func loadInheritedContext() async {
        guard let metadata = atom.metadataValue(as: ContentAtomMetadata.self) else { return }

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
        hooks = metadata.inheritedHooks ?? []

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

        // Derive niche from atom metadata for targeted queries
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        var niche: String?
        if let clientUUID = metadata?.clientProfileUUID,
           let client = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = client.metadataValue(as: ClientProfileMetadata.self) {
            niche = clientMeta.niche
        }

        // --- Primary tier: Same format research swipes ---
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
            print("ContentContextPanel: primary tier search failed: \(error)")
        }

        // --- Secondary tier: Same niche content atoms ---
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
            print("ContentContextPanel: secondary tier search failed: \(error)")
        }

        // --- Tertiary tier: Broad semantic search ---
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
            print("ContentContextPanel: tertiary tier search failed: \(error)")
        }

        relatedContent = allRefs
    }

    private func debounceRelatedRefresh() {
        guard state.currentStep == .draft else { return }

        relatedSearchTask?.cancel()
        relatedSearchTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            guard !Task.isCancelled else { return }
            await refreshRelatedContent()
        }
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
