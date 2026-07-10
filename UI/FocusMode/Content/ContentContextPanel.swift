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
    @State private var margin = ContentMarginModel()
    @State private var isGeneratingDraft = false
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
        hasDraftIntelligence || margin.hasAnyShelf
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
                    .fill(DS.entityContent.opacity(0.1))
                    .frame(width: 1)
            }
            .onAppear {
                margin.bind(atomUUID: atom.uuid)
                Task {
                    await loadInheritedContext()
                    isLoading = false
                }
            }
            .onChange(of: state.draftContent) {
                margin.noteDraftChanged(atom: atom, state: state)
            }
        }
    }

    // MARK: - Header

    private var panelHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "link.circle.fill")
                .font(DS.body)
                .foregroundStyle(accentColor)

            Text("Context")
                .font(DS.callout)
                .fontWeight(.semibold)
                .foregroundStyle(DS.text)

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
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
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
                .foregroundStyle(DS.textMuted.opacity(0.5))

            VStack(spacing: 4) {
                Text("Start writing to build context")
                    .font(DS.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.textMuted)

                Text("Context from linked ideas, swipes,\nand research will appear here")
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted.opacity(0.7))
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
                    .font(DS.caption)
                    .foregroundStyle(CosmoMentionColors.idea)

                VStack(alignment: .leading, spacing: 3) {
                    Text(idea.title ?? "Untitled Idea")
                        .font(DS.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.text)
                        .lineLimit(2)

                    if let body = idea.body, !body.isEmpty {
                        Text(String(body.prefix(80)))
                            .font(DS.caption2)
                            .foregroundStyle(DS.textMuted)
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
                    .foregroundStyle(DS.textMuted)
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
                .foregroundStyle(status.color)
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
        .foregroundStyle(DS.textMuted)
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
                    .font(DS.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)

                Spacer()

                // Hook type badge if available
                if let swipeAnalysis = swipe.swipeAnalysis,
                   let hookType = swipeAnalysis.hookType {
                    Text(hookType.displayName)
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(DS.entitySwipe)
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
            sectionHeader(title: "CONCEPTS", icon: "link.circle.fill")

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
                Text(conn.title ?? "Concept")
                    .font(DS.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(DS.text)
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
            .foregroundStyle(color)
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
                .font(DS.caption)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)
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
                .font(DS.caption2.weight(.bold))
                .foregroundStyle(accentColor)
                .frame(width: 16)

            Text(hook)
                .font(DS.caption2)
                .foregroundStyle(DS.textSecondary)
                .lineLimit(3)

            Spacer(minLength: 4)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hook, forType: .string)
            } label: {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 9))
                    .foregroundStyle(DS.textMuted)
                    .frame(width: 24, height: 24)
                    .background(DS.glassCardFill, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Intelligence Section (Collapsible)

    @ViewBuilder
    private var intelligenceSection: some View {
        if hasIntelligenceData || margin.isRefreshing {
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
                    draftIntelligenceSubsection
                    marginShelves
                }
            }
        }
    }

    @ViewBuilder
    private var intelligenceHeaderLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: showIntelligence ? "chevron.down" : "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(DS.textMuted)
                .frame(width: 12)

            Image(systemName: "brain.head.profile")
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)

            Text("Intelligence")
                .dsSmallCapsLabel()

            Spacer()

            let count = intelligenceItemCount
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(accentColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(0.12), in: Capsule())
            }
        }
    }

    private var intelligenceItemCount: Int {
        var count = 0
        if hasDraftIntelligence { count += 1 }
        count += margin.totalCount
        return count
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
                        .foregroundStyle(DS.textMuted)
                    Text("Draft Intelligence")
                        .dsSmallCapsLabel()
                }

                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(DS.caption2)
                        .foregroundStyle(DS.entitySwipe)
                    Text("\(swipeUUIDs.count) matched swipe\(swipeUUIDs.count == 1 ? "" : "s")")
                        .font(DS.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(DS.textSecondary)
                }

                if let draftPackageData = atom.structured,
                   let data = draftPackageData.data(using: .utf8),
                   let draftPackage = try? JSONDecoder().decode(ContentDraftPackage.self, from: data) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(DS.caption2)
                            .foregroundStyle(DS.accent)
                        Text("Confidence: \(String(format: "%.0f%%", draftPackage.confidence * 100))")
                            .font(DS.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(DS.textSecondary)
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
                .font(DS.caption2)
                .fontWeight(.medium)
        }
        .foregroundStyle(DS.textSecondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(DS.accent.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var draftButtonContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(DS.caption2)
            Text("Generate Draft")
                .font(DS.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(DS.text)
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

    // MARK: - The Margin (ambient recall shelves)

    @ViewBuilder
    private var marginShelves: some View {
        marginShelf(
            title: "CONCEPTS",
            icon: "link",
            tint: CosmoMentionColors.connection,
            hits: margin.concepts
        )
        marginShelf(
            title: "SWIPES",
            icon: "bolt.fill",
            tint: DS.entitySwipe,
            hits: margin.swipes
        )
        marginShelf(
            title: "NOTES & IDEAS",
            icon: "note.text",
            tint: CosmoMentionColors.note,
            hits: margin.notes
        )
    }

    /// Silence over noise: an empty shelf renders nothing at all.
    @ViewBuilder
    private func marginShelf(
        title: String,
        icon: String,
        tint: Color,
        hits: [RecallHit]
    ) -> some View {
        if !hits.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 9))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                    Text(title)
                        .dsSmallCapsLabel()
                }
                VStack(spacing: 4) {
                    ForEach(hits) { hit in
                        marginRow(hit, tint: tint)
                    }
                }
            }
        }
    }

    private func marginRow(_ hit: RecallHit, tint: Color) -> some View {
        MarginSuggestionRow(
            hit: hit,
            tint: tint,
            typeIcon: iconForAtomType(hit.atomType),
            onOpen: {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": hit.atomUuid, "asPane": true]
                )
            },
            onDismiss: { margin.dismiss(hit) }
        )
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundStyle(DS.textMuted)
            Text(title)
                .dsSmallCapsLabel()
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

        // Prime the Margin from the intent signal (title + dek + format +
        // niche) — no draft required, so suggestions exist from second zero.
        await margin.refresh(atom: atom, state: state)
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
