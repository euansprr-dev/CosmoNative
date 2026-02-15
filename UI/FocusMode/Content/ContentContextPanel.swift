// CosmoOS/UI/FocusMode/Content/ContentContextPanel.swift
// Collapsible right sidebar showing inherited idea context for Content Focus Mode
// February 2026

import SwiftUI

// MARK: - Content Context Panel

/// Collapsible right sidebar that shows the inherited context chain:
/// Source Idea → Matched Swipes → Framework → Hooks → Related Content
struct ContentContextPanel: View {
    let atom: Atom
    @Binding var state: ContentFocusModeState
    let isVisible: Bool

    @State private var sourceIdea: Atom?
    @State private var matchedSwipeAtoms: [Atom] = []
    @State private var selectedFramework: String?
    @State private var hooks: [String] = []
    @State private var relatedContent: [RelatedAtomRef] = []
    @State private var isLoadingRelated = false
    @State private var relatedSearchTask: Task<Void, Never>?
    @State private var isGeneratingDraft = false

    private let panelWidth: CGFloat = 320
    private let accentColor = CosmoMentionColors.content // Blue

    var body: some View {
        if isVisible {
            VStack(spacing: 0) {
                panelHeader

                Divider().background(Color.white.opacity(0.08))

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        sourceIdeaSection
                        matchedSwipesSection
                        frameworkSection
                        hooksSection
                        draftIntelligenceSection
                        relatedContentSection
                        researchButton
                    }
                    .padding(16)
                }
            }
            .frame(width: panelWidth)
            .background(CosmoColors.thinkspaceSecondary.opacity(0.5))
            .onAppear {
                Task { await loadInheritedContext() }
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
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Source Idea Section

    @ViewBuilder
    private var sourceIdeaSection: some View {
        sectionHeader(title: "SOURCE IDEA", icon: "lightbulb.fill")

        if let idea = sourceIdea {
            sourceIdeaCard(idea)
        } else {
            emptySourceIdea
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
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let ideaMeta = idea.ideaMetadata,
                       let status = ideaMeta.ideaStatus {
                        ideaStatusBadge(status)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
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

    private var emptySourceIdea: some View {
        HStack(spacing: 8) {
            Image(systemName: "lightbulb")
                .font(.system(size: 12))
                .foregroundColor(.white.opacity(0.3))
            Text("Link an Idea")
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Matched Swipes Section

    @ViewBuilder
    private var matchedSwipesSection: some View {
        if !matchedSwipeAtoms.isEmpty {
            sectionHeader(title: "MATCHED SWIPES", icon: "doc.on.doc.fill")

            VStack(spacing: 6) {
                ForEach(matchedSwipeAtoms, id: \.uuid) { swipe in
                    swipeCard(swipe)
                }
            }
        }
    }

    private func swipeCard(_ swipe: Atom) -> some View {
        Button {
            NotificationCenter.default.post(
                name: CosmoNotification.Navigation.openBlockInFocusMode,
                object: nil,
                userInfo: ["atomUUID": swipe.uuid]
            )
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#FFD700"))

                Text(swipe.title ?? "Untitled Swipe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(2)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.white.opacity(0.2))
            }
            .padding(10)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Framework Section

    @ViewBuilder
    private var frameworkSection: some View {
        if let framework = selectedFramework, !framework.isEmpty {
            sectionHeader(title: "FRAMEWORK", icon: "rectangle.3.group.fill")

            HStack(spacing: 8) {
                Text(framework)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(accentColor.opacity(0.12), in: Capsule())

                Spacer()

                Button {
                    print("ContentContextPanel: Switch Framework tapped (placeholder)")
                } label: {
                    Text("Switch")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06), in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Hooks Section

    @ViewBuilder
    private var hooksSection: some View {
        if !hooks.isEmpty {
            sectionHeader(title: "HOOKS", icon: "text.quote")

            VStack(spacing: 6) {
                ForEach(Array(hooks.enumerated()), id: \.offset) { index, hook in
                    hookCard(hook, index: index)
                }
            }
        }
    }

    private func hookCard(_ hook: String, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(hook)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.75))
                .lineLimit(3)

            HStack(spacing: 8) {
                hookActionButton(label: "Copy", icon: "doc.on.clipboard") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(hook, forType: .string)
                }

                hookActionButton(label: "Insert", icon: "text.insert") {
                    if state.draftContent.isEmpty {
                        state.draftContent = hook
                    } else {
                        state.draftContent += "\n\n" + hook
                    }
                    state.save()
                }
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func hookActionButton(label: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9))
                Text(label)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundColor(.white.opacity(0.5))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.white.opacity(0.06), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Draft Intelligence Section

    @ViewBuilder
    private var draftIntelligenceSection: some View {
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        let swipeUUIDs = metadata?.inheritedSwipeUUIDs ?? []

        if !swipeUUIDs.isEmpty {
            sectionHeader(title: "DRAFT INTELLIGENCE", icon: "sparkles")

            VStack(alignment: .leading, spacing: 10) {
                // Swipe match count
                HStack(spacing: 8) {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#FFD700"))
                    Text("\(swipeUUIDs.count) matched swipe\(swipeUUIDs.count == 1 ? "" : "s")")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                }

                // Confidence indicator
                if let draftPackageData = atom.structured,
                   let data = draftPackageData.data(using: .utf8),
                   let draftPackage = try? JSONDecoder().decode(ContentDraftPackage.self, from: data) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                        Text("Confidence: \(String(format: "%.0f%%", draftPackage.confidence * 100))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.7))
                    }
                }

                // Generate Draft button
                if metadata?.draftReady == true && state.draftContent.isEmpty {
                    Button(action: { generateDraftFromPanel() }) {
                        if isGeneratingDraft {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .scaleEffect(0.6)
                                    .tint(.white)
                                Text("Generating...")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(Color.purple.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            draftButtonContent
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isGeneratingDraft)
                } else if metadata?.draftReady == false {
                    Text(metadata?.draftingNote ?? "Need more swipes for AI drafting")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.3))
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.purple.opacity(0.2), lineWidth: 1)
            )
        }
    }

    @ViewBuilder
    private var draftButtonContent: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11))
            Text("Generate Draft")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color.purple, in: RoundedRectangle(cornerRadius: 8))
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

    // MARK: - Related Content Section (Tiered)

    @ViewBuilder
    private var relatedContentSection: some View {
        sectionHeader(title: "RELATED", icon: "link")

        if isLoadingRelated {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Searching...")
                    .font(.system(size: 10))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(10)
        } else if relatedContent.isEmpty {
            Text("No related content found")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .padding(10)
        } else {
            VStack(spacing: 12) {
                ForEach(RelatedContentTier.allCases, id: \.rawValue) { tier in
                    let tierItems = relatedContent.filter { $0.tier == tier }
                    if !tierItems.isEmpty {
                        tierGroup(tier: tier, items: tierItems)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func tierGroup(tier: RelatedContentTier, items: [RelatedAtomRef]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tier.accentColor)
                    .frame(width: 6, height: 6)
                Text(tier.label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.6)
                    .foregroundColor(tier.accentColor)
            }

            VStack(spacing: 4) {
                ForEach(items) { ref in
                    relatedContentCard(ref)
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
            HStack(spacing: 0) {
                // Tier accent bar
                RoundedRectangle(cornerRadius: 1)
                    .fill(ref.tier.accentColor)
                    .frame(width: 2, height: 32)
                    .padding(.trailing, 8)

                Image(systemName: iconForAtomType(ref.type))
                    .font(.system(size: 10))
                    .foregroundColor(colorForAtomType(ref.type))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ref.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)

                    if !ref.preview.isEmpty {
                        Text(ref.preview)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.35))
                            .lineLimit(1)
                    }
                }
                .padding(.leading, 6)

                Spacer()

                Text(String(format: "%.0f%%", ref.relevanceScore * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            .padding(8)
            .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Research Button

    private var researchButton: some View {
        Button {
            print("ContentContextPanel: Research This Topic tapped (placeholder)")
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 13))
                Text("Research This Topic")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(accentColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .padding(.top, 8)
    }

    // MARK: - Section Header

    private func sectionHeader(title: String, icon: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.35))
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundColor(.white.opacity(0.35))
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

        selectedFramework = metadata.inheritedFramework
        hooks = metadata.inheritedHooks ?? []

        // Search related content
        await refreshRelatedContent()
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
           let clientMeta = client.metadataValue(as: ClientMetadata.self) {
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
        // Only refresh during draft step
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
