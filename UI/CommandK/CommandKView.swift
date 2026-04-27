// CosmoOS/UI/CommandK/CommandKView.swift
// Cosmo Cortex — Spotlight-inspired morphing Command-K interface
// Three modes: Compact (bubbles + recents) → Search Results → Expanded Domain

import SwiftUI

// MARK: - CommandKView

public struct CommandKView: View {

    // MARK: - Compatibility alias (MainView references CommandKView.CommandKTab)
    typealias CommandKTab = CosmoOS.CommandKTab

    // MARK: - State
    var initialTab: CommandKTab?
    @StateObject private var viewModel = CommandKViewModel()
    @FocusState private var isSearchFocused: Bool
    @Namespace private var cortexNamespace

    init(initialTab: CommandKTab = .database) {
        if initialTab == .database {
            self.initialTab = nil
        } else {
            self.initialTab = initialTab
        }
    }

    // MARK: - Body

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundLayer
                panelContainer(geometry: geometry)
            }
            .ignoresSafeArea()
            .onAppear {
                viewModel.initialExpandedTab = initialTab
                viewModel.initializeCortexMode()
                isSearchFocused = true
            }
        }
        .onKeyPress(.escape) { handleEscape() }
        .onKeyPress(.downArrow) { viewModel.selectNext(); return .handled }
        .onKeyPress(.upArrow) { viewModel.selectPrevious(); return .handled }
        .onKeyPress(.return) { viewModel.openSelected(); return .handled }
        .onKeyPress(.tab) { handleTab() }
    }

    // MARK: - Background

    private var backgroundLayer: some View {
        // Lighter backdrop than FloatingOverlayBackdrop — just a dim scrim
        // so the glass panels can blur the actual app content underneath.
        Color.black.opacity(0.3)
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture {
                NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
            }
    }

    // MARK: - Panel Container

    private func panelContainer(geometry: GeometryProxy) -> some View {
        VStack(spacing: DS.space12) {
            searchBarPill(geometry: geometry)
            contentPanel(geometry: geometry)
        }
        .frame(width: panelWidth(for: geometry))
        .animation(ProMotionSprings.gentle, value: viewModel.cortexMode)
    }

    // MARK: - Search Bar Pill (Spotlight-style)

    private func searchBarPill(geometry: GeometryProxy) -> some View {
        HStack(spacing: DS.space12) {
            // Back button in expanded mode
            if case .expandedDomain = viewModel.cortexMode {
                Button {
                    withAnimation(ProMotionSprings.modal) {
                        viewModel.returnToCompact()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(DS.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(DS.textSecondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }

            // Search icon
            Image(systemName: searchIcon)
                .font(DS.title2)
                .foregroundStyle(isSearchFocused ? DS.accent : DS.textSecondary)
                .symbolEffect(.pulse, isActive: viewModel.currentPhase == .searching)
                .frame(width: 22)

            // Text field
            TextField(searchPlaceholder, text: $viewModel.query)
                .textFieldStyle(.plain)
                .font(DS.title2)
                .foregroundStyle(DS.text)
                .focused($isSearchFocused)
                .onSubmit { viewModel.openSelected() }

            Spacer()

            // Type prefix badge
            if let prefixType = viewModel.activeTypePrefix {
                typePrefixBadge(prefixType)
            }

            // Task creation hint
            if viewModel.isTaskCreationMode {
                Text("Enter to create task")
                    .font(DS.caption)
                    .foregroundStyle(DS.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(DS.accent.opacity(0.12), in: Capsule())
            }

            // Domain bubbles inline (compact mode only)
            if viewModel.cortexMode == .compact {
                domainBubblesInline
            }

            // Expanded domain title
            if case .expandedDomain(let tab) = viewModel.cortexMode {
                expandedTabChip(tab)
            }

            // Voice button
            voiceButton

            // Loading spinner
            if viewModel.currentPhase == .searching {
                ProgressView()
                    .scaleEffect(0.7)
                    .tint(DS.textSecondary)
            }
        }
        .padding(.horizontal, DS.space20)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.15), radius: 24, x: 0, y: 10)
    }

    // MARK: - Domain Bubbles (inline in search bar)

    private var domainBubblesInline: some View {
        HStack(spacing: DS.space6) {
            ForEach(CommandKTab.allCases, id: \.rawValue) { tab in
                CortexInlineBubble(
                    tab: tab,
                    count: viewModel.domainCounts[tab] ?? 0,
                    namespace: cortexNamespace
                ) {
                    withAnimation(ProMotionSprings.snappy) {
                        viewModel.transitionToExpanded(tab)
                    }
                }
            }
        }
    }

    // MARK: - Content Panel

    @ViewBuilder
    private func contentPanel(geometry: GeometryProxy) -> some View {
        switch viewModel.cortexMode {
        case .compact:
            if viewModel.recentItems.isEmpty {
                EmptyView()
            } else {
                compactContent
                    .fixedSize(horizontal: false, vertical: true)
                    .cortexGlassPanel()
            }
        case .searchResults:
            CortexSearchResultsView(viewModel: viewModel)
                .frame(maxHeight: min(geometry.size.height * 0.65, 600))
                .cortexGlassPanel()
        case .expandedDomain(let tab):
            expandedDomainContent(tab)
                .frame(maxHeight: min(max(geometry.size.height * 0.60, 480), 700))
                .cortexGlassPanel()
        }
    }

    // MARK: - Compact Content

    private var compactContent: some View {
        VStack(spacing: 0) {
            if !viewModel.recentItems.isEmpty {
                recentsSection
                    .padding(DS.space20)
            }
            keyboardHintBar
                .padding(.horizontal, DS.space20)
                .padding(.bottom, DS.space12)
        }
    }

    private var keyboardHintBar: some View {
        HStack(spacing: DS.space16) {
            keyHint(keys: "↑↓", label: "Navigate")
            keyHint(keys: "↵", label: "Open")
            keyHint(keys: "⎋", label: "Close")
            Spacer()
        }
    }

    private func keyHint(keys: String, label: String) -> some View {
        HStack(spacing: DS.space4) {
            Text(keys)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(DS.textMuted)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(DS.glassCardFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(DS.border.opacity(0.15), lineWidth: 0.5)
                )
            Text(label)
                .font(DS.caption2)
                .foregroundStyle(DS.textMuted)
        }
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: DS.space12) {
            Text("RECENTS")
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.textMuted)
                .tracking(0.5)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: DS.space12)],
                spacing: DS.space12
            ) {
                ForEach(Array(viewModel.recentItems.enumerated()), id: \.element.id) { index, item in
                    CortexRecentCard(item: item) {
                        viewModel.openRecent(item)
                    } onDelete: {
                        viewModel.deleteRecent(item)
                    }
                    .transition(.opacity.combined(with: .offset(y: 6)))
                    .animation(ProMotionSprings.staggered(index: index), value: viewModel.recentItems.count)
                }
            }
        }
    }

    // MARK: - Expanded Domain Content

    @ViewBuilder
    private func expandedDomainContent(_ tab: CommandKTab) -> some View {
        VStack(spacing: 0) {
            // Domain header bar
            HStack(spacing: DS.space8) {
                Image(systemName: tab.icon)
                    .font(DS.callout)
                    .foregroundStyle(tab.accentColor)

                Text(tab.title)
                    .font(DS.headline)
                    .foregroundStyle(DS.text)

                Spacer()

                Text("\(viewModel.domainCounts[tab] ?? 0) items")
                    .font(DS.caption)
                    .foregroundStyle(DS.textMuted)
            }
            .padding(.horizontal, DS.space20)
            .frame(height: 40)

            Divider().foregroundStyle(DS.border.opacity(0.3))

            // Cortex-native compact browsers (640px purpose-built)
            switch tab {
            case .database:
                CortexDatabaseBrowser(viewModel: viewModel)
            case .swipeGallery:
                CortexSwipeBrowser(viewModel: viewModel)
            case .ideas:
                CortexIdeasBrowser(viewModel: viewModel)
            case .readwise:
                CortexReadwiseBrowser(viewModel: viewModel)
            case .inquiry:
                CortexInquiryBrowser(viewModel: viewModel)
            }
        }
    }

    // MARK: - Expanded Tab Chip

    private func expandedTabChip(_ tab: CommandKTab) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: tab.icon)
                .font(DS.caption2)
            Text(tab.title)
                .font(DS.caption)
        }
        .foregroundStyle(tab.accentColor)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tab.accentColor.opacity(0.12), in: Capsule())
    }

    // MARK: - Voice Button

    private var voiceButton: some View {
        Button {
            viewModel.isVoiceActive.toggle()
        } label: {
            Image(systemName: viewModel.isVoiceActive ? "mic.fill" : "mic")
                .font(DS.callout)
                .foregroundStyle(viewModel.isVoiceActive ? DS.accent : DS.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(viewModel.isVoiceActive ? DS.accent.opacity(0.15) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type Prefix Badge

    @ViewBuilder
    private func typePrefixBadge(_ type: AtomType) -> some View {
        HStack(spacing: DS.space4) {
            Image(systemName: iconForType(type))
                .font(DS.caption2)
            Text(type.displayName)
                .font(DS.caption)
        }
        .foregroundStyle(entityColor(type))
        .padding(.horizontal, DS.space8)
        .padding(.vertical, DS.space4)
        .background(entityColor(type).opacity(0.15), in: Capsule())
    }

    // MARK: - Panel Sizing

    private func panelWidth(for geometry: GeometryProxy) -> CGFloat {
        let availableWidth = max(320, geometry.size.width - 96)

        switch viewModel.cortexMode {
        case .compact:
            return min(CommandKMetrics.compactWidth, availableWidth)
        case .searchResults:
            return min(CommandKMetrics.searchWidth, availableWidth)
        case .expandedDomain(let tab):
            let targetWidth: CGFloat = tab == .ideas ? 1320 : 900
            return min(targetWidth, availableWidth)
        }
    }

    // MARK: - Helpers

    private var searchIcon: String {
        viewModel.isTaskCreationMode ? "plus.circle.fill" : "magnifyingglass"
    }

    private var searchPlaceholder: String {
        if case .expandedDomain(let tab) = viewModel.cortexMode {
            return tab.searchPlaceholder
        }
        return "Spotlight Search"
    }

    private func entityColor(_ type: AtomType) -> Color {
        switch type {
        case .idea: return DS.entityIdea
        case .task: return DS.entityTask
        case .content: return DS.entityContent
        case .research: return DS.entityResearch
        case .connection: return DS.entityConnection
        case .project: return DS.entityIdea
        default: return DS.textSecondary
        }
    }

    private func iconForType(_ type: AtomType) -> String {
        switch type {
        case .idea: return "lightbulb.fill"
        case .task: return "checkmark.circle.fill"
        case .research: return "book.fill"
        case .content: return "doc.text.fill"
        case .connection: return "doc.fill"
        case .project: return "folder.fill"
        default: return "circle.fill"
        }
    }

    // MARK: - Keyboard Handlers

    private func handleEscape() -> KeyPress.Result {
        switch viewModel.cortexMode {
        case .expandedDomain:
            if viewModel.isMultiSelectActive {
                withAnimation(ProMotionSprings.snappy) {
                    viewModel.clearSelection()
                }
            } else {
                withAnimation(ProMotionSprings.modal) {
                    viewModel.returnToCompact()
                }
            }
        case .searchResults:
            viewModel.query = ""
        case .compact:
            NotificationCenter.default.post(name: CosmoNotification.NodeGraph.closeCommandK, object: nil)
        }
        return .handled
    }

    private func handleTab() -> KeyPress.Result {
        return .handled
    }
}

// MARK: - Inline Bubble (inside search bar)

/// Small circular bubble shown inline in the search bar (compact mode).
/// Tapping expands to full domain view.
private struct CortexInlineBubble: View {
    let tab: CommandKTab
    let count: Int
    let namespace: Namespace.ID
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? tab.accentColor.opacity(0.18) : tab.accentColor.opacity(0.08))

                Circle()
                    .stroke(isHovered ? tab.accentColor.opacity(0.35) : DS.border.opacity(0.2), lineWidth: 0.5)

                Image(systemName: tab.icon)
                    .font(DS.caption)
                    .foregroundStyle(tab.accentColor)
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
            .matchedGeometryEffect(id: "cortexDomain-\(tab.rawValue)", in: namespace)
            .overlay(alignment: .top) {
                // Count badge on hover
                if isHovered && count > 0 {
                    Text("\(count)")
                        .font(DS.caption2)
                        .foregroundStyle(tab.accentColor)
                        .padding(.horizontal, DS.space4)
                        .padding(.vertical, 1)
                        .background(tab.accentColor.opacity(0.15), in: Capsule())
                        .offset(y: -14)
                        .transition(.opacity.combined(with: .offset(y: 4)))
                }
            }
        }
        .buttonStyle(.borderless)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .accessibilityLabel("\(tab.title), \(count) items")
    }
}

// MARK: - Preview

#Preview("Cortex - Compact") {
    CommandKView()
        .frame(width: 1200, height: 800)
}

#Preview("Cortex - Expanded") {
    CommandKView(initialTab: .swipeGallery)
        .frame(width: 1200, height: 800)
}
