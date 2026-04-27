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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabBar
            Divider().background(DS.borderSubtle)
            if let activeTab {
                sourceAttachmentBar(activeTab)
                Divider().background(DS.borderSubtle)
            }
            if !viewModel.structured.sourceRefs.isEmpty {
                sourceLibrary
                Divider().background(DS.borderSubtle)
            }
            if showingURLEntry || viewModel.structured.sourceTabs.isEmpty {
                urlEntryRow
                    .padding(.horizontal, DS.space16)
                    .padding(.vertical, DS.space10)
                Divider().background(DS.borderSubtle)
            }
            if viewModel.structured.sourceTabs.isEmpty {
                emptyState
            } else if let activeTab = activeTab {
                ZStack(alignment: .bottom) {
                    tabContent(activeTab)
                    if !lastSelectedText.isEmpty {
                        selectionMiniMenu(for: activeTab)
                            .padding(DS.space12)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
            } else {
                emptyState
            }
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
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
        guard let id = viewModel.activeSourceTabId else { return viewModel.structured.sourceTabs.first }
        return viewModel.structured.sourceTabs.first { $0.id == id } ?? viewModel.structured.sourceTabs.first
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
        VStack(spacing: DS.space12) {
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 30))
                .foregroundStyle(DS.accent.opacity(0.45))
            Text("Drop a source or paste a URL to begin.")
                .font(CosmoTypography.body)
                .foregroundStyle(CosmoColors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
