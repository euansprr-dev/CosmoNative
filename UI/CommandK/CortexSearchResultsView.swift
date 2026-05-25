// CosmoOS/UI/CommandK/CortexSearchResultsView.swift
// Grouped search results for Cortex search mode — sections by source with "See all" navigation

import SwiftUI

struct CortexSearchResultsView: View {
    @ObservedObject var viewModel: CommandKViewModel
    var openDomain: (CommandKTab) -> Void

    var body: some View {
        let swipeItemsByUUID = Dictionary(uniqueKeysWithValues: viewModel.swipeGalleryItems.map { ($0.atomUUID, $0) })
        let ideaItemsByUUID = Dictionary(uniqueKeysWithValues: viewModel.ideaGalleryItems.map { ($0.atomUUID, $0) })

        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: DS.space16) {
                    HStack(spacing: DS.space8) {
                        Image(systemName: "sparkles.square.filled.on.square")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.text)
                            .accessibilityHidden(true)
                        Text("Smart Results")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(DS.text)
                    }

                    if let action = viewModel.primaryAction {
                        CommandKActionPreviewRow(
                            action: action,
                            isExecuting: viewModel.isExecutingAction,
                            statusMessage: viewModel.actionStatusMessage
                        ) {
                            viewModel.performPrimaryAction()
                        }
                    }

                    if let bestMatch = viewModel.unifiedFlatResults.first {
                        CommandKBestMatchCard(result: bestMatch) {
                            selectResult(bestMatch)
                        }
                    }

                    ForEach(Array(viewModel.unifiedGroupedResults.enumerated()), id: \.element.source) { _, group in
                        if !group.results.isEmpty {
                            CortexSearchSection(
                                source: group.source,
                                results: group.results,
                                selectedId: viewModel.selectedNodeId,
                                libraryItemsByID: viewModel.unifiedLibraryItemsByID,
                                swipeItemsByUUID: swipeItemsByUUID,
                                ideaItemsByUUID: ideaItemsByUUID,
                                onSeeAll: { seeAll(group.source) },
                                onSelect: { selectResult($0) }
                            )
                        }
                    }

                    if viewModel.primaryAction == nil,
                       viewModel.unifiedGroupedResults.allSatisfy({ $0.results.isEmpty }),
                       viewModel.searchFeedback.matches(query: viewModel.query) {
                        emptyState
                    }
                }
                .padding(DS.space24)
            }
            .onChange(of: viewModel.selectedResultIndex) { _, newIndex in
                guard newIndex >= 0, newIndex < viewModel.unifiedFlatResults.count else { return }
                let result = viewModel.unifiedFlatResults[newIndex]
                withAnimation(ProMotionSprings.snappy) {
                    proxy.scrollTo(result.selectionID, anchor: .center)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 28))
                .foregroundStyle(DS.textMuted)
            Text("No results found")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space32)
    }

    private func seeAll(_ source: UnifiedSearchSource) {
        let tab: CommandKTab? = switch source {
        case .atoms: .database
        case .swipes: .swipeGallery
        case .ideas: .ideas
        case .readwise: .readwise
        case .browser: nil
        }
        guard let tab else { return }
        openDomain(tab)
    }

    private func selectResult(_ result: UnifiedSearchResult) {
        viewModel.selectedNodeId = result.selectionID
        if let idx = viewModel.unifiedFlatResults.firstIndex(where: { $0.selectionID == result.selectionID }) {
            viewModel.selectedResultIndex = idx
        }
        viewModel.openSelected()
    }
}

// MARK: - Best Match

private struct CommandKBestMatchCard: View {
    let result: UnifiedSearchResult
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DS.space16) {
                preview
                content
            }
            .padding(DS.space16)
            .frame(maxWidth: .infinity, minHeight: 174, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [DS.accent.opacity(0.96), Color(hex: "10301F")],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(isHovered ? 0.36 : 0.18), lineWidth: 0.7)
            )
            .shadow(color: DS.accent.opacity(isHovered ? 0.22 : 0.12), radius: isHovered ? 24 : 16, x: 0, y: 8)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .commandKSearchResultContextMenu(result: result)
    }

    private var preview: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: 180, height: 130)
            .overlay {
                VStack(spacing: DS.space10) {
                    Image(systemName: result.icon)
                        .font(.system(size: 34, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                    Text(result.source.displayName)
                        .font(DS.caption)
                        .foregroundStyle(.white.opacity(0.64))
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.5)
            )
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.space8) {
            Text("Best match")
                .font(DS.caption)
                .foregroundStyle(.white.opacity(0.78))

            Text(result.title)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(DS.callout)
                    .foregroundStyle(.white.opacity(0.74))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack(spacing: DS.space10) {
                actionPill("Open", icon: "arrow.up.right.square")
                actionPill("Attach", icon: "paperclip")
                actionPill("Canvas", icon: "square.grid.2x2")
            }
        }
    }

    private func actionPill(_ title: String, icon: String) -> some View {
        HStack(spacing: DS.space6) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
            Text(title)
                .font(DS.callout)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space10)
        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

// MARK: - Fast Action Preview

private struct CommandKActionPreviewRow: View {
    let action: CommandKAction
    let isExecuting: Bool
    let statusMessage: String?
    let onRun: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onRun) {
            HStack(spacing: 14) {
                actionIcon

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: DS.space8) {
                        Text(action.title)
                            .font(DS.headline)
                            .foregroundStyle(DS.text)
                            .lineLimit(1)

                        if !action.isExecutable {
                            Text("Needs input")
                                .font(DS.caption2)
                                .foregroundStyle(DS.orange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(DS.orangeSoft, in: Capsule())
                        }
                    }

                    if let message = statusMessage, !message.isEmpty {
                        Text(message)
                            .font(DS.caption)
                            .foregroundStyle(message == "Working..." ? DS.textMuted : DS.red)
                            .lineLimit(1)
                    } else if let subtitle = action.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(DS.caption)
                            .foregroundStyle(DS.textMuted)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: DS.space16)

                trailingControl
            }
            .padding(.horizontal, 14)
            .padding(.vertical, DS.space12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isHovered ? DS.glassInputFillFocused : DS.glassCardFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isHovered ? DS.glassBorderFocused : DS.glassBorder, lineWidth: 0.5)
            )
            .shadow(color: DS.sidebarMaterialShadow.opacity(isHovered ? 0.45 : 0.25), radius: isHovered ? 14 : 8, y: isHovered ? 6 : 3)
        }
        .buttonStyle(.plain)
        .disabled(isExecuting)
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) {
                isHovered = hovering
            }
        }
        .accessibilityLabel(action.title)
        .accessibilityHint(action.isExecutable ? "Run action" : "Add the missing detail first")
    }

    private var actionIcon: some View {
        Image(systemName: action.icon)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(accentColor)
            .frame(width: 34, height: 34)
            .background(accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(accentColor.opacity(0.22), lineWidth: 0.5)
            )
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isExecuting {
            ProgressView()
                .scaleEffect(0.75)
                .tint(DS.textMuted)
        } else {
            HStack(spacing: DS.space6) {
                Text(action.isExecutable ? "Run" : "Waiting")
                    .font(DS.caption)
                Text("Return")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(DS.glassInputFill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            .foregroundStyle(action.isExecutable ? accentColor : DS.textMuted)
        }
    }

    private var accentColor: Color {
        switch action.kind {
        case .captureSwipe, .captureSwipeWithIdea:
            return DS.entitySwipe
        case .createIdea:
            return DS.entityIdea
        case .createTask:
            return DS.entityTask
        case .captureResearch, .captureLane, .createCaptureLane:
            return DS.entityResearch
        case .createContent:
            return DS.entityContent
        case .createThinkspace, .navigateLastThinkspace, .openThinkspace:
            return DS.entityConnection
        case .navigateCommandCenter, .openBrowser, .openDomain, .openApp, .openAtom, .savedSearch:
            return DS.accent
        case .openCosmoPane, .openCosmoWindow, .askCosmo:
            return DS.gilt
        }
    }
}

// MARK: - Search Section

private struct CortexSearchSection: View {
    let source: UnifiedSearchSource
    let results: [UnifiedSearchResult]
    let selectedId: String?
    let libraryItemsByID: [String: LibraryItem]
    let swipeItemsByUUID: [String: SwipeGalleryItem]
    let ideaItemsByUUID: [String: IdeaGalleryItem]
    let onSeeAll: () -> Void
    let onSelect: (UnifiedSearchResult) -> Void

    private let databaseCardWidth: CGFloat = 126
    private let swipeCardWidth: CGFloat = 148

    /// Max items to show per section
    private var maxItems: Int {
        switch source {
        case .atoms: return 8
        case .swipes: return 4
        case .ideas: return 3
        case .readwise: return 3
        case .browser: return 6
        }
    }

    private var visibleAtomResults: [(result: UnifiedSearchResult, item: LibraryItem)] {
        results.prefix(maxItems).compactMap { result in
            guard let key = result.libraryLookupKey,
                  let item = libraryItemsByID[key] else { return nil }
            return (result, item)
        }
    }

    private var visibleSwipeResults: [(result: UnifiedSearchResult, item: SwipeGalleryItem)] {
        results.prefix(maxItems).compactMap { result in
            guard let atomUUID = result.atomUUID,
                  let item = swipeItemsByUUID[atomUUID] else { return nil }
            return (result, item)
        }
    }

    private var visibleIdeaResults: [(result: UnifiedSearchResult, item: IdeaGalleryItem)] {
        results.prefix(maxItems).compactMap { result in
            guard let atomUUID = result.atomUUID,
                  let item = ideaItemsByUUID[atomUUID] else { return nil }
            return (result, item)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.space10) {
            sectionHeader
            sectionContent
        }
        .padding(DS.space16)
        .background(DS.glassCardFill.opacity(0.28), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.64), lineWidth: 0.5)
        )
    }

    private var sectionHeader: some View {
        HStack(spacing: DS.space6) {
            Image(systemName: source.icon)
                .font(DS.callout)
                .foregroundStyle(source.accentColor)

            Text(source.displayName)
                .font(DS.headline)
                .foregroundStyle(DS.text)

            Text("\(results.count)")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)
            Text("results")
                .font(DS.caption)
                .foregroundStyle(DS.textMuted)

            Spacer()

            if source != .browser && results.count > maxItems {
                Button(action: onSeeAll) {
                    HStack(spacing: 3) {
                        Text("See all")
                            .font(DS.caption)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .foregroundStyle(source.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch source {
        case .atoms:
            atomPreviewStrip
        case .swipes:
            swipePreviewStrip
        case .ideas:
            ideaPreviewList
        case .readwise:
            readwisePreviewStrip
        case .browser:
            browserPinPreviewStrip
        }
    }

    private var atomPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(visibleAtomResults, id: \.result.id) { entry in
                    SpotlightDocCard(
                        item: entry.item,
                        onTap: { onSelect(entry.result) },
                        onDelete: {
                            Task { try? await AtomRepository.shared.delete(uuid: entry.item.uuid) }
                        }
                    )
                    .frame(width: databaseCardWidth)
                    .id(entry.result.selectionID)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var swipePreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: DS.space12) {
                ForEach(visibleSwipeResults, id: \.result.id) { entry in
                    CortexSwipeThumb(item: entry.item) {
                        onSelect(entry.result)
                    }
                    .frame(width: swipeCardWidth, alignment: .top)
                    .id(entry.result.selectionID)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
    }

    private var ideaPreviewList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(visibleIdeaResults.enumerated()), id: \.element.result.id) { index, entry in
                IdeaMaterialLedgerRow(item: entry.item) {
                    onSelect(entry.result)
                }
                .id(entry.result.selectionID)

                if index < visibleIdeaResults.count - 1 {
                    Rectangle()
                        .fill(DS.glassBorder.opacity(0.55))
                        .frame(height: 0.5)
                        .padding(.leading, DS.space12)
                }
            }
        }
        .padding(DS.space12)
        .background(DS.glassCardFill.opacity(0.30), in: RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.radiusLarge, style: .continuous)
                .stroke(DS.glassBorder.opacity(0.74), lineWidth: 0.5)
        )
        .shadow(color: DS.sidebarMaterialShadow.opacity(0.42), radius: 10, y: 4)
    }

    private var readwisePreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space12) {
                ForEach(results.prefix(maxItems)) { result in
                    CortexSearchCard(
                        result: result,
                        isSelected: selectedId == result.selectionID,
                        onSelect: { onSelect(result) }
                    )
                    .id(result.selectionID)
                }
            }
        }
    }

    private var browserPinPreviewStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DS.space12) {
                ForEach(results.prefix(maxItems)) { result in
                    CortexSearchCard(
                        result: result,
                        isSelected: selectedId == result.selectionID,
                        onSelect: { onSelect(result) }
                    )
                    .id(result.selectionID)
                }
            }
        }
    }
}

// MARK: - Search Card (for Swipes/Readwise)

private struct CortexSearchCard: View {
    let result: UnifiedSearchResult
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DS.space8) {
                cardPreview
                cardTitle
            }
            .frame(width: 160)
            .padding(DS.space10)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(
                color: .black.opacity(isHovered ? 0.07 : 0.03),
                radius: isHovered ? 10 : 5,
                x: 0,
                y: isHovered ? 3 : 1
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(ProMotionSprings.hover, value: isHovered)
        .commandKSearchResultContextMenu(result: result)
    }

    private var cardPreview: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(result.accentColor.opacity(0.08))
            .frame(height: 80)
            .overlay {
                Image(systemName: result.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(result.accentColor.opacity(0.4))
            }
    }

    private var cardTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(result.title)
                .font(DS.caption)
                .fontWeight(.medium)
                .foregroundStyle(DS.text)
                .lineLimit(2)

            if let subtitle = result.subtitle {
                Text(subtitle)
                    .font(DS.caption2)
                    .foregroundStyle(DS.textMuted)
                    .lineLimit(1)
            }
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(DS.glassCardFill.opacity(isHovered ? 0.7 : 0.4))
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(isSelected ? DS.accent.opacity(0.4) : DS.border.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.5)
    }
}
