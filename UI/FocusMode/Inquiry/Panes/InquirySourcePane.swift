// CosmoOS/UI/FocusMode/Inquiry/Panes/InquirySourcePane.swift
// Source pane (Pane B). Phase 3:
//   - Web sources via WKWebView with reader-mode toggle (WebSourceView).
//   - Internal sources (Note / Research / Swipe) via InternalSourceView.
//   - Tab bar with branch awareness, URL/quick-open input, selection mini-menu.

import SwiftUI

@MainActor
struct InquirySourcePane: View {
    @Bindable var viewModel: InquiryWorkspaceViewModel

    @State private var showingURLEntry = false
    @State private var urlEntry: String = ""
    @State private var lastSelectedText: String = ""
    @State private var readerMode: Bool = true
    @State private var showSaveAsMenu: Bool = false
    @State private var sourceSearchDraft: String = ""
    @State private var sourceSearchMode: InquirySourceSearchMode = .quick

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Divider().background(DS.borderSubtle)
            if let activeTab {
                sourceAttachmentBar(activeTab)
                Divider().background(DS.borderSubtle)
                if !viewModel.structured.sourceRefs.isEmpty {
                    sourceLibrary
                    Divider().background(DS.borderSubtle)
                }
            }
            if showingURLEntry {
                urlEntryRow
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space10)
                Divider().background(DS.borderSubtle)
            }
            if let activeTab {
                ZStack(alignment: .bottom) {
                    tabContent(activeTab)
                    if !lastSelectedText.isEmpty {
                        selectionMiniMenu(for: activeTab)
                            .padding(DS.space12)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            } else {
                sourceRadar
            }
        }
        .onAppear { syncSearchModeFromBatch() }
        .onChange(of: viewModel.activeRecommendationBatch?.id) { _, _ in
            syncSearchModeFromBatch()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                radarTabChip
                ForEach(viewModel.structured.sourceTabs, id: \.id) { tab in
                    tabChip(tab)
                }
                Button {
                    showingURLEntry.toggle()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                        .padding(6)
                        .background(DS.surfaceHover, in: Circle())
                        .foregroundStyle(CosmoColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Open source")
                Spacer()
                if let activeTab = activeTab, activeTab.kind == .web {
                    readerToggle
                }
            }
            .padding(.horizontal, DS.space16)
            .padding(.vertical, DS.space10)
        }
    }

    private var radarTabChip: some View {
        let isActive = activeTab == nil
        return Button {
            viewModel.activeSourceTabId = nil
            lastSelectedText = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 10, weight: .semibold))
                Text("Source Radar")
                    .font(CosmoTypography.caption)
                    .lineLimit(1)
                if !viewModel.activeSourceCandidates.isEmpty {
                    Text("\(viewModel.activeSourceCandidates.count)")
                        .font(CosmoTypography.caption)
                        .padding(.horizontal, 4)
                        .background(DS.accentSoft, in: Capsule())
                }
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(isActive ? DS.surfaceHover : Color.clear, in: Capsule())
            .foregroundStyle(isActive ? CosmoColors.textPrimary : CosmoColors.textSecondary)
            .overlay(Capsule().stroke(isActive ? DS.borderActive : DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Source Radar")
    }

    private var readerToggle: some View {
        Button {
            readerMode.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: readerMode ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 10))
                Text(readerMode ? "Reader" : "Raw")
                    .font(CosmoTypography.caption)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
            .foregroundStyle(CosmoColors.textSecondary)
        }
        .buttonStyle(.plain)
    }

    private func tabChip(_ tab: SourceTab) -> some View {
        let isActive = viewModel.activeSourceTabId == tab.id
        return Button {
            viewModel.activeSourceTabId = tab.id
            lastSelectedText = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: tabIcon(for: tab.kind))
                    .font(.system(size: 10))
                Text(tab.title)
                    .font(CosmoTypography.caption)
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .leading)
                if tab.highlightCount > 0 {
                    Text("\(tab.highlightCount)")
                        .font(CosmoTypography.caption)
                        .padding(.horizontal, 4)
                        .background(DS.accentSoft, in: Capsule())
                }
                if let q = tab.attachedQuestionUUID {
                    Text(String(viewModel.questionTitle(for: q).prefix(18)))
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .padding(.horizontal, 5)
                        .background(DS.surface, in: Capsule())
                }
                Button {
                    viewModel.closeSourceTab(tab.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8))
                        .foregroundStyle(CosmoColors.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 4)
            .background(isActive ? DS.surfaceHover : Color.clear, in: Capsule())
            .foregroundStyle(isActive ? CosmoColors.textPrimary : CosmoColors.textSecondary)
            .overlay(Capsule().stroke(isActive ? DS.borderActive : DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func sourceAttachmentBar(_ tab: SourceTab) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 11))
                .foregroundStyle(CosmoColors.textTertiary)
            Text("Attached to")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
            Menu {
                ForEach(viewModel.orderedQuestionNodes(), id: \.id) { node in
                    Button {
                        attach(tab: tab, toQuestionUUID: node.atomUUID, nodeId: node.id)
                    } label: {
                        Text(viewModel.questionTitle(for: node.atomUUID))
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(viewModel.questionTitle(for: tab.attachedQuestionUUID ?? viewModel.activeQuestionUUID))
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(CosmoColors.textTertiary)
                }
            }
            .buttonStyle(.plain)
            Spacer()
            if tab.highlightCount > 0 {
                Text("\(tab.highlightCount) extracts")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, 7)
    }

    private func attach(tab: SourceTab, toQuestionUUID questionUUID: String?, nodeId: String) {
        viewModel.attachSourceTab(tab, toQuestionUUID: questionUUID, nodeId: nodeId)
    }

    private func tabIcon(for kind: SourceTab.Kind) -> String {
        switch kind {
        case .web: return "globe"
        case .pdf: return "doc.text"
        case .youTube: return "play.rectangle"
        case .internalAtom: return "note.text"
        case .swipe: return "bookmark"
        }
    }

    private var activeTab: SourceTab? {
        guard let id = viewModel.activeSourceTabId else { return nil }
        return viewModel.structured.sourceTabs.first { $0.id == id }
    }

    private var sourceLibrary: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack {
                Text("SESSION SOURCES")
                    .font(CosmoTypography.labelSmall)
                    .tracking(1.6)
                    .foregroundStyle(CosmoColors.textTertiary)
                Spacer()
                Text("\(viewModel.structured.sourceRefs.count)")
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.space8) {
                    ForEach(viewModel.structured.sourceRefs.filter { $0.status != .archived && $0.status != .deleted }, id: \.sourceUUID) { ref in
                        sourceLibraryChip(ref)
                    }
                }
            }
        }
        .padding(.horizontal, DS.space16)
        .padding(.vertical, DS.space10)
    }

    private func sourceLibraryChip(_ ref: InquirySourceRef) -> some View {
        let isOpen = ref.tabId.flatMap { id in viewModel.structured.sourceTabs.contains { $0.id == id } } ?? false
        return Button {
            viewModel.reopenSource(ref)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOpen ? "doc.text.fill" : "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(isOpen ? DS.accent : CosmoColors.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(ref.title)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textSecondary)
                        .lineLimit(1)
                    Text("\(viewModel.questionTitle(for: ref.primaryQuestionUUID)) · \(ref.status.displayName)")
                        .font(CosmoTypography.labelSmall)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(width: 188, alignment: .leading)
            .padding(.horizontal, DS.space8)
            .padding(.vertical, 6)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - URL entry

    private var urlEntryRow: some View {
        HStack(spacing: DS.space8) {
            Image(systemName: "link")
                .foregroundStyle(CosmoColors.textTertiary)
            TextField("Paste URL or search…", text: $urlEntry)
                .textFieldStyle(.plain)
                .font(CosmoTypography.body)
                .onSubmit { Task { await openURLEntry() } }
            Button("Open") { Task { await openURLEntry() } }
                .buttonStyle(.plain)
                .font(CosmoTypography.label)
                .padding(.horizontal, DS.space10)
                .padding(.vertical, 6)
                .background(DS.accent, in: Capsule())
                .foregroundStyle(DS.textOnAccent)
                .keyboardShortcut(.return, modifiers: [])
                .disabled(urlEntry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func openURLEntry() async {
        let trimmed = urlEntry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await viewModel.openURLSource(trimmed)
        urlEntry = ""
        showingURLEntry = false
    }

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(_ tab: SourceTab) -> some View {
        switch tab.kind {
        case .web:
            if let urlString = tab.url, let url = URL(string: urlString) {
                WebSourceView(url: url, readerMode: readerMode, lastSelectedText: $lastSelectedText)
            } else {
                tabUnavailable
            }
        case .internalAtom, .swipe:
            if let uuid = tab.sourceUUID {
                InternalSourceView(sourceUUID: uuid, lastSelectedText: $lastSelectedText)
            } else {
                tabUnavailable
            }
        case .pdf, .youTube:
            // V1.1: PDFKit + YouTube transcript wiring.
            phasedComingSoonView(for: tab)
        }
    }

    private var tabUnavailable: some View {
        VStack(spacing: DS.space12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22))
                .foregroundStyle(DS.orange)
            Text("Source unavailable.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func phasedComingSoonView(for tab: SourceTab) -> some View {
        VStack(spacing: DS.space12) {
            Image(systemName: tabIcon(for: tab.kind))
                .font(.system(size: 28))
                .foregroundStyle(DS.accent.opacity(0.5))
            Text(tab.title)
                .font(CosmoTypography.titleSmall)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("\(tab.kind.rawValue.uppercased()) viewer ships in V1.1.")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection mini-menu

    private func selectionMiniMenu(for tab: SourceTab) -> some View {
        HStack(spacing: 6) {
            Menu {
                ForEach(ExtractKind.allCases, id: \.self) { kind in
                    Button(kind.displayName) {
                        Task { await saveSelection(as: kind, fromTab: tab) }
                    }
                }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
                    .font(CosmoTypography.label)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .padding(.horizontal, DS.space10)
            .padding(.vertical, 6)
            .background(DS.accent, in: Capsule())
            .foregroundStyle(DS.textOnAccent)

            Button {
                Task {
                    await viewModel.runAIPrompt("About this selection from \(tab.title): \(lastSelectedText)\n\nExplain what this means in relation to the active question: \(viewModel.activeQuestionTitle). If it should become a branch or objection, say so briefly.")
                    lastSelectedText = ""
                }
            } label: {
                Label("Ask", systemImage: "sparkles")
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
                    .foregroundStyle(CosmoColors.textPrimary)
            }
            .buttonStyle(.plain)

            Button {
                Task { await deepenFromSelection(tab) }
            } label: {
                Label("Deepen", systemImage: "arrow.triangle.branch")
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 6)
                    .overlay(Capsule().stroke(DS.borderSubtle, lineWidth: 1))
                    .foregroundStyle(CosmoColors.textPrimary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("d", modifiers: [.command])

            Button {
                lastSelectedText = ""
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11))
                    .padding(6)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(DS.surfaceElevated, in: Capsule())
        .overlay(Capsule().stroke(DS.borderActive, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
    }

    private func saveSelection(as kind: ExtractKind, fromTab tab: SourceTab) async {
        let body = lastSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            let extract = try await InquiryRepository.shared.createExtract(
                body: body,
                kind: kind,
                sourceUUID: tab.sourceUUID,
                selectionRange: nil,
                sessionUUID: viewModel.session.uuid,
                questionUUID: viewModel.activeQuestionUUID,
                deepDiveUUID: viewModel.deepDive?.uuid,
                branchNodeId: viewModel.activeBranchNodeId,
                sourceTabId: tab.id,
                userNote: nil,
                originType: "highlight",
                citation: tab.url ?? tab.title
            )
            viewModel.registerSavedExtract(extract, sourceTabId: tab.id)
            viewModel.scheduleSave()
            lastSelectedText = ""
        } catch {
            print("[InquirySourcePane] saveSelection failed: \(error)")
        }
    }

    private func deepenFromSelection(_ tab: SourceTab) async {
        let body = lastSelectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        // 1. Save extract first so we have an origin
        let extractAtom: Atom?
        do {
            extractAtom = try await InquiryRepository.shared.createExtract(
                body: body,
                kind: .highlight,
                sourceUUID: tab.sourceUUID,
                selectionRange: nil,
                sessionUUID: viewModel.session.uuid,
                questionUUID: viewModel.activeQuestionUUID,
                deepDiveUUID: viewModel.deepDive?.uuid,
                branchNodeId: viewModel.activeBranchNodeId,
                sourceTabId: tab.id,
                userNote: nil,
                originType: "deepen",
                citation: tab.url ?? tab.title
            )
        } catch {
            print("[InquirySourcePane] deepen extract failed: \(error)")
            extractAtom = nil
        }
        if let extractAtom {
            viewModel.registerSavedExtract(extractAtom, sourceTabId: tab.id)
        }

        // 2. Auto-title the branch question (V1: just use selection prefix)
        viewModel.proposeBranchFromSelection(body, originExtractUUID: extractAtom?.uuid, sourceTabId: tab.id)
        lastSelectedText = ""
    }

    // MARK: - Empty state

    private var emptyState: some View {
        sourceRadar
    }

    private var sourceRadar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.space16) {
                sourceRadarHeader
                sourceSearchBar
                providerStatusStrip
                scoutTrail
                if viewModel.isRefreshingSources && viewModel.activeSourceCandidates.isEmpty {
                    radarLoadingState
                } else if viewModel.activeSourceCandidates.isEmpty {
                    radarEmptyState
                } else {
                    LazyVStack(spacing: DS.space10) {
                        ForEach(sourceRadarCandidateGroups.indices, id: \.self) { index in
                            let group = sourceRadarCandidateGroups[index]
                            sourceLaneHeader(group)
                            ForEach(group.candidates, id: \.id) { candidate in
                                sourceCandidateCard(candidate)
                            }
                        }
                    }
                }
            }
            .padding(DS.space20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(DS.bg)
    }

    private var sourceRadarHeader: some View {
        HStack(alignment: .top, spacing: DS.space12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "scope")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.accent)
                    Text("SOURCE RADAR")
                        .font(CosmoTypography.labelSmall)
                        .tracking(1.8)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
                Text("Top sources for this branch")
                    .font(CosmoTypography.titleSmall)
                    .foregroundStyle(CosmoColors.textPrimary)
                Text(viewModel.activeQuestionTitle)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                Task { await viewModel.refreshSourceRecommendations(mode: sourceSearchMode) }
            } label: {
                Image(systemName: viewModel.isRefreshingSources ? "arrow.clockwise.circle.fill" : "arrow.clockwise")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .background(DS.surfaceElevated, in: Circle())
                    .overlay(Circle().stroke(DS.borderSubtle, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DS.accent)
            .help("Refresh Source Radar")
        }
    }

    private var providerStatusStrip: some View {
        let statuses = viewModel.activeRecommendationBatch?.providerStatuses ?? []
        return HStack(spacing: 6) {
            if viewModel.isRefreshingSources {
                radarChip(sourceSearchMode == .deepScout ? "Deep Scout running" : "Searching", icon: "arrow.clockwise", tint: DS.accent)
            } else if statuses.isEmpty {
                radarChip("Ready", icon: "sparkle.magnifyingglass", tint: DS.accent)
            } else {
                ForEach(statuses, id: \.provider) { status in
                    radarChip(
                        "\(status.provider.displayName) \(status.count)",
                        icon: providerIcon(for: status),
                        tint: tint(for: status)
                    )
                    .help(status.message ?? status.state.rawValue)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var sourceSearchBar: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            HStack(spacing: DS.space10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.accent)
                TextField("Find sources about nasal breathing, HRV, CO2 tolerance...", text: $sourceSearchDraft)
                    .textFieldStyle(.plain)
                    .font(CosmoTypography.bodySmall)
                    .onSubmit { searchSourcesFromRadar() }
                    .disabled(viewModel.isRefreshingSources)
                Picker("Search mode", selection: $sourceSearchMode) {
                    ForEach(InquirySourceSearchMode.allCases, id: \.self) { mode in
                        Label(mode.displayName, systemImage: mode.iconName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 176)
                Button {
                    searchSourcesFromRadar()
                } label: {
                    HStack(spacing: 6) {
                        if viewModel.isRefreshingSources {
                            ProgressView()
                                .controlSize(.small)
                                .scaleEffect(0.62)
                        }
                        Text(sourceSearchButtonTitle)
                    }
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space10)
                    .padding(.vertical, 6)
                    .background(sourceSearchButtonBackground, in: Capsule())
                    .foregroundStyle(sourceSearchButtonForeground)
                }
                .buttonStyle(.plain)
                .disabled(sourceSearchDisabled)
            }
            .padding(.horizontal, DS.space12)
            .padding(.vertical, DS.space10)
            .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
            .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))

            if let activity = viewModel.sourceActivityLine {
                sourceActivityLine(activity)
            } else if let query = viewModel.activeRecommendationBatch?.query, !query.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: viewModel.activeRecommendationBatch?.searchMode.iconName ?? "scope")
                        .font(.system(size: 10, weight: .semibold))
                    Text("\(viewModel.activeRecommendationBatch?.searchMode.displayName ?? "Quick") within branch: \(query)")
                        .lineLimit(1)
                }
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textTertiary)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: viewModel.sourceActivityLine)
    }

    private var sourceSearchTrimmedDraft: String {
        sourceSearchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var sourceSearchDisabled: Bool {
        viewModel.isRefreshingSources || sourceSearchTrimmedDraft.isEmpty
    }

    private var sourceSearchButtonTitle: String {
        if viewModel.isRefreshingSources {
            return sourceSearchMode == .deepScout ? "Scouting" : "Searching"
        }
        return sourceSearchMode == .deepScout ? "Scout" : "Search"
    }

    private var sourceSearchButtonBackground: Color {
        sourceSearchDisabled && !viewModel.isRefreshingSources ? DS.surfaceHover : DS.accent
    }

    private var sourceSearchButtonForeground: Color {
        sourceSearchDisabled && !viewModel.isRefreshingSources ? CosmoColors.textTertiary : DS.textOnAccent
    }

    private func sourceActivityLine(_ activity: String) -> some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.58)
            Text(activity)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(sourceSearchMode == .deepScout ? "Deep Scout" : "Quick")
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(DS.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(DS.accent.opacity(0.08), in: Capsule())
        }
        .font(CosmoTypography.caption)
        .foregroundStyle(CosmoColors.textSecondary)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 6)
        .background(DS.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.accent.opacity(0.14), lineWidth: 1))
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }

    private func searchSourcesFromRadar() {
        let query = sourceSearchTrimmedDraft
        guard !query.isEmpty, !viewModel.isRefreshingSources else { return }
        Task { await viewModel.refreshSourceRecommendations(query: query, mode: sourceSearchMode) }
    }

    private func syncSearchModeFromBatch() {
        guard let mode = viewModel.activeRecommendationBatch?.searchMode,
              sourceSearchMode != mode else { return }
        sourceSearchMode = mode
    }

    @ViewBuilder
    private var scoutTrail: some View {
        if let batch = viewModel.activeRecommendationBatch,
           batch.searchMode == .deepScout,
           !batch.scoutSteps.isEmpty {
            VStack(alignment: .leading, spacing: DS.space8) {
                HStack(spacing: 7) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.accent)
                    Text("SCOUT TRAIL")
                        .font(CosmoTypography.labelSmall)
                        .tracking(1.4)
                        .foregroundStyle(CosmoColors.textTertiary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: DS.space8)], spacing: DS.space8) {
                    ForEach(Array(batch.scoutSteps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: DS.space8) {
                            Text("\(index + 1)")
                                .font(CosmoTypography.labelSmall)
                                .foregroundStyle(DS.accent)
                                .frame(width: 18, height: 18)
                                .background(DS.accent.opacity(0.08), in: Circle())
                            Text(step)
                                .font(CosmoTypography.caption)
                                .foregroundStyle(CosmoColors.textSecondary)
                                .lineLimit(2)
                        }
                        .padding(DS.space8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
                        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
                    }
                }
            }
        }
    }

    private func radarChip(_ title: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(title)
                .font(CosmoTypography.caption)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, DS.space8)
        .padding(.vertical, 5)
        .background(tint.opacity(0.08), in: Capsule())
        .overlay(Capsule().stroke(tint.opacity(0.18), lineWidth: 1))
    }

    private var radarLoadingState: some View {
        VStack(spacing: DS.space10) {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DS.radiusSmall)
                    .fill(DS.surfaceElevated)
                    .frame(height: 94)
                    .redacted(reason: .placeholder)
                    .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
            }
        }
    }

    private var radarEmptyState: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(DS.accent.opacity(0.52))
            Text("No source candidates yet.")
                .font(CosmoTypography.label)
                .foregroundStyle(CosmoColors.textPrimary)
            Text("Search quickly or switch to Deep Scout to search academic indexes, web, YouTube, and your library.")
                .font(CosmoTypography.caption)
                .foregroundStyle(CosmoColors.textSecondary)
                .lineLimit(2)
            Button {
                Task { await viewModel.refreshSourceRecommendations(mode: sourceSearchMode) }
            } label: {
                Label(sourceSearchMode == .deepScout ? "Run Deep Scout" : "Refresh sources", systemImage: sourceSearchMode.iconName)
                    .font(CosmoTypography.label)
                    .padding(.horizontal, DS.space12)
                    .padding(.vertical, 7)
                    .background(DS.accent, in: Capsule())
                    .foregroundStyle(DS.textOnAccent)
            }
            .buttonStyle(.plain)
        }
        .padding(DS.space20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(DS.borderSubtle, lineWidth: 1))
    }

    private var sourceRadarCandidateGroups: [SourceRadarLaneGroup] {
        let grouped = Dictionary(grouping: viewModel.activeSourceCandidates) { candidate in
            candidate.sourceLane ?? fallbackLane(for: candidate)
        }
        return sourceRadarLaneOrder.compactMap { lane in
            guard let candidates = grouped[lane], !candidates.isEmpty else { return nil }
            return SourceRadarLaneGroup(lane: lane, candidates: candidates)
        }
    }

    private var sourceRadarLaneOrder: [InquirySourceLane] {
        [
            .localLibrary,
            .primaryText,
            .deepRead,
            .teacherLecture,
            .practiceGuide,
            .scholarlyContext,
            .clinicalEvidence,
            .webResource
        ]
    }

    private func fallbackLane(for candidate: InquirySourceCandidate) -> InquirySourceLane {
        switch candidate.provider {
        case .local:
            return .localLibrary
        case .googleBooks, .openLibrary, .internetArchive:
            return candidate.evidenceRole == .primaryText ? .primaryText : .deepRead
        case .youtube:
            return .teacherLecture
        case .pubMed:
            return .clinicalEvidence
        case .openAlex, .crossref, .semanticScholar, .arxiv:
            return candidate.evidenceRole == .metaAnalysis || candidate.evidenceRole == .review ? .clinicalEvidence : .scholarlyContext
        case .web:
            return .webResource
        }
    }

    private func sourceLaneHeader(_ group: SourceRadarLaneGroup) -> some View {
        HStack(spacing: DS.space8) {
            Image(systemName: group.lane.iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.accent.opacity(0.75))
                .accessibilityHidden(true)
            Text(group.lane.displayName.uppercased())
                .font(CosmoTypography.labelSmall)
                .tracking(1.4)
                .foregroundStyle(CosmoColors.textTertiary)
            Text("\(group.candidates.count)")
                .font(CosmoTypography.labelSmall)
                .foregroundStyle(CosmoColors.textTertiary)
                .monospacedDigit()
            Spacer()
        }
        .padding(.top, DS.space6)
    }

    private func sourceCandidateCard(_ candidate: InquirySourceCandidate) -> some View {
        let lane = candidate.sourceLane ?? fallbackLane(for: candidate)
        return HStack(alignment: .top, spacing: DS.space12) {
            VStack(spacing: 4) {
                Image(systemName: lane.iconName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.accent)
                    .frame(width: 32, height: 32)
                    .background(DS.accentSoft, in: Circle())
                Text("\(Int(candidate.score * 100))")
                    .font(CosmoTypography.labelSmall)
                    .foregroundStyle(CosmoColors.textTertiary)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: DS.space8) {
                    Text(candidate.title)
                        .font(CosmoTypography.label)
                        .foregroundStyle(CosmoColors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: DS.space8)
                    sourceLanePill(lane)
                }
                if let subtitle = candidate.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CosmoTypography.caption)
                        .foregroundStyle(CosmoColors.textTertiary)
                        .lineLimit(1)
                }
                Text(candidate.reason)
                    .font(CosmoTypography.caption)
                    .foregroundStyle(CosmoColors.textSecondary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    radarMetadata("\(candidate.provider.displayName) · \(candidate.evidenceRole.displayName)")
                    if let year = candidate.publishedDate?.prefix(4), !year.isEmpty {
                        radarMetadata(String(year))
                    }
                    ForEach(candidate.qualitySignals.prefix(2), id: \.self) { signal in
                        radarMetadata(signal)
                    }
                }
            }
            candidateActions(candidate)
        }
        .padding(DS.space12)
        .background(DS.surfaceElevated, in: RoundedRectangle(cornerRadius: DS.radiusSmall))
        .overlay(RoundedRectangle(cornerRadius: DS.radiusSmall).stroke(candidate.importStatus == .imported ? DS.accent.opacity(0.28) : DS.borderSubtle, lineWidth: 1))
    }

    private func sourceLanePill(_ lane: InquirySourceLane) -> some View {
        HStack(spacing: 4) {
            Image(systemName: lane.iconName)
                .font(.system(size: 9, weight: .semibold))
                .accessibilityHidden(true)
            Text(lane.displayName)
        }
        .font(CosmoTypography.labelSmall)
        .foregroundStyle(DS.accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(DS.accent.opacity(0.08), in: Capsule())
    }

    private func evidenceRolePill(_ role: InquiryEvidenceRole) -> some View {
        Text(role.displayName)
            .font(CosmoTypography.labelSmall)
            .foregroundStyle(DS.accent)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(DS.accent.opacity(0.08), in: Capsule())
    }

    private func radarMetadata(_ text: String) -> some View {
        Text(text)
            .font(CosmoTypography.labelSmall)
            .foregroundStyle(CosmoColors.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(DS.surface, in: Capsule())
    }

    private func candidateActions(_ candidate: InquirySourceCandidate) -> some View {
        HStack(spacing: 4) {
            Button {
                Task { await viewModel.importSourceCandidate(candidate) }
            } label: {
                Image(systemName: candidate.importStatus == .imported ? "checkmark.circle.fill" : "arrow.down.doc")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(candidate.importStatus == .imported ? DS.accent : CosmoColors.textSecondary)
            .help(candidate.importStatus == .imported ? "Already imported" : "Import source")

            Button {
                viewModel.queueSourceCandidate(candidate)
            } label: {
                Image(systemName: candidate.importStatus == .queued ? "tray.fill" : "tray.and.arrow.down")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(candidate.importStatus == .queued ? DS.accent : CosmoColors.textSecondary)
            .help("Queue source")

            Button {
                viewModel.dismissSourceCandidate(candidate)
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .foregroundStyle(CosmoColors.textTertiary)
            .help("Dismiss")
        }
    }

    private func providerIcon(for status: InquiryProviderStatus) -> String {
        switch status.state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed, .rateLimited, .missingKey: return "exclamationmark.circle"
        case .loading: return "arrow.clockwise"
        case .idle: return "circle"
        }
    }

    private func tint(for status: InquiryProviderStatus) -> Color {
        switch status.state {
        case .succeeded: return DS.accent
        case .failed, .rateLimited, .missingKey: return DS.orange
        case .loading, .idle: return CosmoColors.textTertiary
        }
    }
}

private struct SourceRadarLaneGroup {
    var lane: InquirySourceLane
    var candidates: [InquirySourceCandidate]
}
