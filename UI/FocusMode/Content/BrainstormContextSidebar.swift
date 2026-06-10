// CosmoOS/UI/FocusMode/Content/BrainstormContextSidebar.swift
// Premium context discovery sidebar for Brainstorm step — Thinkspace-style design
// February 2026

import SwiftUI

// MARK: - Sidebar Mode

private enum SidebarMode: Equatable {
    case discovery
    case detail(String) // atomUUID

    static func == (lhs: SidebarMode, rhs: SidebarMode) -> Bool {
        switch (lhs, rhs) {
        case (.discovery, .discovery): return true
        case (.detail(let a), .detail(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - Brainstorm Context Sidebar

/// Collapsible right sidebar that surfaces related swipes, ideas, research, and content
/// using Nomic embeds via HybridSearchEngine. Tapping an item replaces the feed with
/// that item's full detail view.
struct BrainstormContextSidebar: View {
    let atom: Atom
    @Binding var state: ContentFocusModeState
    @Binding var isVisible: Bool

    @State private var sidebarMode: SidebarMode = .discovery
    @State private var discoveryResults: [RelatedAtomRef] = []
    @State private var isSearching = false
    @State private var detailAtom: Atom?
    @State private var detailLoadTask: Task<Void, Never>?
    @State private var detailRequestID = UUID()
    @State private var searchTask: Task<Void, Never>?
    @State private var searchRequestID = UUID()
    @State private var hoveredItemID: UUID?

    private let sidebarWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            switch sidebarMode {
            case .discovery:
                discoveryView
            case .detail:
                detailView
            }
        }
        .frame(width: sidebarWidth)
        .background(sidebarBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 16, x: -4, y: 0)
        .transition(.move(edge: .trailing).combined(with: .opacity))
        .onAppear { runDiscoverySearch() }
        .onChange(of: state.contentDescription) { _, _ in debounceSearch() }
        .onDisappear {
            searchTask?.cancel()
            searchTask = nil
            detailLoadTask?.cancel()
            detailLoadTask = nil
        }
    }

    // MARK: - Background

    private var sidebarBackground: some View {
        ZStack {
            DS.surface
            LinearGradient(
                colors: [
                    DS.accent.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topTrailing,
                endPoint: .bottomLeading
            )
        }
    }

    // MARK: - Discovery View

    private var discoveryView: some View {
        VStack(spacing: 0) {
            discoveryHeader

            Divider().background(DS.border)

            if isSearching && discoveryResults.isEmpty {
                searchingIndicator
            } else if discoveryResults.isEmpty {
                emptyState
            } else {
                discoveryList
            }
        }
    }

    private var discoveryHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(DS.accent.opacity(0.6))

            Text("DISCOVER")
                .dsSectionLabel()

            Spacer()

            if isSearching {
                ProgressView()
                    .controlSize(.mini)
                    .tint(DS.accent.opacity(0.4))
            }

            closeButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var closeButton: some View {
        Button {
            withAnimation(ProMotionSprings.snappy) {
                isVisible = false
            }
        } label: {
            Image(systemName: "sidebar.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DS.textMuted)
                .padding(5)
                .background(DS.border, in: RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }

    private var searchingIndicator: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.regular)
                .tint(DS.accent.opacity(0.3))
            Text("Searching knowledge base...")
                .font(DS.timestamp)
                .foregroundStyle(DS.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer().frame(height: 48)

            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(DS.accent.opacity(0.15))

            Text("Enter a description to discover\nrelated swipes, research & content")
                .font(DS.cardMeta)
                .foregroundStyle(DS.textMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var discoveryList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(RelatedContentTier.allCases, id: \.rawValue) { tier in
                    let tierItems = discoveryResults.filter { $0.tier == tier }
                    if !tierItems.isEmpty {
                        discoveryTierSection(tier: tier, items: tierItems)
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Tier Section

    @ViewBuilder
    private func discoveryTierSection(tier: RelatedContentTier, items: [RelatedAtomRef]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Tier header
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(tier.accentColor)
                    .frame(width: 12, height: 2)

                Text(tier.label)
                    .font(DS.smallCaps)
                    .foregroundStyle(tier.accentColor)

                Spacer()

                Text("\(items.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textMuted)
            }

            // Cards
            ForEach(items) { ref in
                discoveryCardButton(ref: ref, tier: tier)
            }
        }
    }

    private func discoveryCardButton(ref: RelatedAtomRef, tier: RelatedContentTier) -> some View {
        let isHovered = hoveredItemID == ref.id
        return Button {
            openDetail(atomUUID: ref.atomUUID)
        } label: {
            discoveryCardLabel(ref: ref, tier: tier, isHovered: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                hoveredItemID = hovering ? ref.id : nil
            }
        }
    }

    @ViewBuilder
    private func discoveryCardLabel(ref: RelatedAtomRef, tier: RelatedContentTier, isHovered: Bool) -> some View {
        HStack(spacing: 0) {
            // Tier accent bar
            RoundedRectangle(cornerRadius: 1)
                .fill(tier.accentColor)
                .frame(width: 2, height: 38)
                .padding(.trailing, 10)

            // Type icon
            Image(systemName: ref.type.iconName)
                .font(.system(size: 10))
                .foregroundStyle(colorForAtomType(ref.type))
                .frame(width: 16)

            // Title + preview
            VStack(alignment: .leading, spacing: 2) {
                Text(ref.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isHovered ? DS.text : DS.text.opacity(0.85))
                    .lineLimit(1)

                if !ref.preview.isEmpty {
                    Text(ref.preview)
                        .font(.system(size: 9))
                        .foregroundStyle(DS.textMuted)
                        .lineLimit(2)
                }
            }
            .padding(.leading, 8)

            Spacer(minLength: 6)

            // Score + chevron
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.0f%%", ref.relevanceScore * 100))
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.textMuted)

                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(isHovered ? DS.textMuted : DS.textMuted.opacity(0.5))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(isHovered ? DS.border : DS.borderSubtle)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .stroke(isHovered ? DS.borderActive : DS.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - Detail View

    private var detailView: some View {
        VStack(spacing: 0) {
            detailHeader

            Divider().background(DS.border)

            if let detail = detailAtom {
                detailBody(detail)
            } else {
                detailLoading
            }
        }
    }

    private var detailHeader: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(ProMotionSprings.snappy) {
                    sidebarMode = .discovery
                    detailAtom = nil
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DS.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(DS.border, in: RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            if let detail = detailAtom {
                Image(systemName: detail.type.iconName)
                    .font(.system(size: 11))
                    .foregroundStyle(colorForAtomType(detail.type))

                Text(detail.title ?? "Untitled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
            } else {
                Text("Loading")
                    .dsSmallCapsLabel()
            }

            Spacer()

            closeButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var detailLoading: some View {
        VStack {
            Spacer()
            ProgressView()
                .controlSize(.regular)
                .tint(DS.accent.opacity(0.3))
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func detailBody(_ detail: Atom) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Type-specific content
                if detail.isSwipeFileAtom {
                    swipeDetailContent(detail)
                } else if detail.type == .idea {
                    ideaDetailContent(detail)
                } else {
                    genericDetailContent(detail)
                }

                // Body preview
                bodyPreview(detail)

                // Action buttons
                detailActions(detail)
            }
            .padding(14)
        }
    }

    // MARK: - Swipe Detail

    @ViewBuilder
    private func swipeDetailContent(_ detail: Atom) -> some View {
        if let analysis = detail.swipeAnalysis {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("SWIPE ANALYSIS")

                // Hook badge
                if let hookType = analysis.hookType {
                    HStack(spacing: 8) {
                        Image(systemName: hookType.iconName)
                            .font(.system(size: 10))
                            .foregroundStyle(hookType.color)

                        Text(hookType.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(hookType.color)

                        Spacer()

                        if let score = analysis.hookScore {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8))
                                Text(String(format: "%.0f", score * 100))
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                            }
                            .foregroundStyle(DS.textMuted)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(hookType.color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Framework
                if let framework = analysis.frameworkType {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.3.group.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DS.accent.opacity(0.6))
                        Text(framework.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.textSecondary)
                    }
                }
            }
            .padding(10)
            .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(hex: "#FFD700").opacity(0.1), lineWidth: 1)
            )
        }
    }

    // MARK: - Idea Detail

    @ViewBuilder
    private func ideaDetailContent(_ detail: Atom) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("IDEA")

            HStack(spacing: 8) {
                if let status = detail.ideaMetadata?.ideaStatus {
                    ideaStatusChip(status)
                }
                if let format = detail.ideaMetadata?.contentFormat {
                    formatChip(format)
                }
                if let platform = detail.ideaMetadata?.platform {
                    platformChip(platform)
                }
                Spacer()
            }
        }
        .padding(10)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    private func ideaStatusChip(_ status: IdeaStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.displayName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(status.color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12), in: Capsule())
    }

    private func formatChip(_ format: ContentFormat) -> some View {
        HStack(spacing: 3) {
            Image(systemName: format.icon)
                .font(.system(size: 7))
            Text(format.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(format.color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(format.color.opacity(0.12), in: Capsule())
    }

    private func platformChip(_ platform: IdeaPlatform) -> some View {
        HStack(spacing: 3) {
            Image(systemName: platform.iconName)
                .font(.system(size: 7))
            Text(platform.displayName)
                .font(.system(size: 9, weight: .medium))
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.border, in: Capsule())
    }

    // MARK: - Generic Detail

    @ViewBuilder
    private func genericDetailContent(_ detail: Atom) -> some View {
        HStack(spacing: 6) {
            Image(systemName: detail.type.iconName)
                .font(.system(size: 9))
                .foregroundStyle(colorForAtomType(detail.type))
            Text(detail.type.displayName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(colorForAtomType(detail.type))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(colorForAtomType(detail.type).opacity(0.12), in: Capsule())
    }

    // MARK: - Body Preview

    private func bodyPreview(_ detail: Atom) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("CONTENT")

            let bodyText = detail.body ?? ""
            if bodyText.isEmpty {
                Text("No content")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textMuted)
                    .italic()
            } else {
                Text(String(bodyText.prefix(800)))
                    .font(.system(size: 11))
                    .foregroundStyle(DS.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(DS.borderSubtle, in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Detail Actions

    private func detailActions(_ detail: Atom) -> some View {
        VStack(spacing: 6) {
            // Open in Focus Mode
            Button {
                NotificationCenter.default.post(
                    name: CosmoNotification.Navigation.openBlockInFocusMode,
                    object: nil,
                    userInfo: ["atomUUID": detail.uuid]
                )
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right.square.fill")
                        .font(.system(size: 11))
                    Text("Open in Focus Mode")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DS.text)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(colorForAtomType(detail.type).opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(colorForAtomType(detail.type).opacity(0.3), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            // Copy + Insert row
            HStack(spacing: 6) {
                if let body = detail.body, !body.isEmpty {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(body, forType: .string)
                    } label: {
                        actionChipLabel(icon: "doc.on.clipboard", text: "Copy")
                    }
                    .buttonStyle(.plain)

                    Button {
                        if state.contentDescription.isEmpty {
                            state.contentDescription = body
                        } else {
                            state.contentDescription += "\n\n" + body
                        }
                        state.save()
                    } label: {
                        actionChipLabel(icon: "text.insert", text: "Insert")
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
    }

    @ViewBuilder
    private func actionChipLabel(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(text)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(DS.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(DS.border, in: Capsule())
    }

    // MARK: - Shared

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .dsSectionLabel()
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

    // MARK: - Search Logic

    private func openDetail(atomUUID: String) {
        detailLoadTask?.cancel()
        let requestID = UUID()
        detailRequestID = requestID

        withAnimation(ProMotionSprings.snappy) {
            sidebarMode = .detail(atomUUID)
            detailAtom = nil
        }
        detailLoadTask = Task {
            do {
                let fetched = try await AtomRepository.shared.fetch(uuid: atomUUID)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard detailRequestID == requestID else { return }
                    withAnimation(ProMotionSprings.snappy) {
                        detailAtom = fetched
                    }
                }
            } catch {
                guard !Task.isCancelled else { return }
                print("BrainstormContextSidebar: Failed to load detail: \(error)")
                await MainActor.run {
                    guard detailRequestID == requestID else { return }
                    withAnimation(ProMotionSprings.snappy) {
                        sidebarMode = .discovery
                    }
                }
            }
        }
    }

    private func debounceSearch() {
        searchTask?.cancel()
        let requestID = UUID()
        searchRequestID = requestID
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s debounce
            guard !Task.isCancelled else { return }
            await performTieredSearch(requestID: requestID)
        }
    }

    private func runDiscoverySearch() {
        searchTask?.cancel()
        let requestID = UUID()
        searchRequestID = requestID
        searchTask = Task {
            await performTieredSearch(requestID: requestID)
        }
    }

    private func performTieredSearch(requestID: UUID) async {
        let query = state.contentDescription.isEmpty ? (atom.title ?? "") : state.contentDescription
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                guard searchRequestID == requestID else { return }
                discoveryResults = []
                isSearching = false
            }
            return
        }

        await MainActor.run {
            guard searchRequestID == requestID else { return }
            isSearching = true
        }

        var allRefs: [RelatedAtomRef] = []
        var seenUUIDs: Set<String> = [atom.uuid]

        // Derive niche
        let metadata = atom.metadataValue(as: ContentAtomMetadata.self)
        var niche: String?
        if let clientUUID = metadata?.clientProfileUUID,
           let client = try? await AtomRepository.shared.fetch(uuid: clientUUID),
           let clientMeta = client.metadataValue(as: ClientProfileMetadata.self) {
            niche = clientMeta.niche
        }

        // --- Primary: research/swipes matching idea + niche ---
        do {
            let primaryQuery = [query, niche].compactMap { $0 }.joined(separator: " ")
            let results = try await HybridSearchEngine.shared.search(
                query: primaryQuery,
                limit: 8,
                entityTypes: [.research]
            )
            for result in results where !seenUUIDs.contains(result.entityUUID ?? "") {
                guard allRefs.filter({ $0.tier == .primary }).count < 4 else { break }
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
            print("BrainstormContextSidebar: primary search failed: \(error)")
        }

        guard !Task.isCancelled else { return }

        // --- Secondary: ideas + content ---
        do {
            let results = try await HybridSearchEngine.shared.search(
                query: niche ?? query,
                limit: 8,
                entityTypes: [.idea, .content]
            )
            for result in results where !seenUUIDs.contains(result.entityUUID ?? "") {
                guard allRefs.filter({ $0.tier == .secondary }).count < 4 else { break }
                let uuid = result.entityUUID ?? ""
                seenUUIDs.insert(uuid)
                allRefs.append(RelatedAtomRef(
                    atomUUID: uuid,
                    title: result.title,
                    type: AtomType(rawValue: result.entityType.rawValue) ?? .idea,
                    relevanceScore: result.combinedScore,
                    preview: result.preview,
                    tier: .secondary
                ))
            }
        } catch {
            print("BrainstormContextSidebar: secondary search failed: \(error)")
        }

        guard !Task.isCancelled else { return }

        // --- Tertiary: broad semantic ---
        do {
            let results = try await HybridSearchEngine.shared.search(
                query: query,
                limit: 10
            )
            for result in results where !seenUUIDs.contains(result.entityUUID ?? "") {
                guard allRefs.filter({ $0.tier == .tertiary }).count < 4 else { break }
                let uuid = result.entityUUID ?? ""
                seenUUIDs.insert(uuid)
                allRefs.append(RelatedAtomRef(
                    atomUUID: uuid,
                    title: result.title,
                    type: AtomType(rawValue: result.entityType.rawValue) ?? .connection,
                    relevanceScore: result.combinedScore,
                    preview: result.preview,
                    tier: .tertiary
                ))
            }
        } catch {
            print("BrainstormContextSidebar: tertiary search failed: \(error)")
        }

        guard !Task.isCancelled else { return }

        await MainActor.run {
            guard searchRequestID == requestID else { return }
            discoveryResults = allRefs
            isSearching = false
        }
    }
}
