// CosmoOS/UI/CommandK/CortexResultRail.swift
// Raycast-style left rail. Decision 1C: no SPACES section — the rail is
// purely Recents (empty query) or live grouped results (query active).
// Decision 2B: single tap selects + previews, double tap / Enter opens.

import SwiftUI

struct CortexResultRail: View {
    @ObservedObject var viewModel: CommandKViewModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.space6) {
                    if viewModel.query.isEmpty {
                        recentsSection
                    } else {
                        resultsSections
                    }
                }
                .padding(DS.space16)
            }
            .scrollIndicators(.hidden)
            .onChange(of: viewModel.selectedResultIndex) { _, _ in
                guard let id = viewModel.selectedNodeId else { return }
                withAnimation(ProMotionSprings.snappy) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    // MARK: Recents (empty query)

    @ViewBuilder
    private var recentsSection: some View {
        if viewModel.recentItems.isEmpty {
            railHint("Search your mind, or pick a recent thread.")
        } else {
            AtelierOrnamentalSectionLabel(label: "RECENTS")
            ForEach(viewModel.recentItems) { item in
                CortexRailRow(
                    title: item.title,
                    subtitle: "\(item.type.displayName) · \(item.relativeDate)",
                    accent: cortexEntityAccent(item.type),
                    thumbnailURL: item.thumbnailURL,
                    previewText: item.preview,
                    isConnection: item.type == .connection,
                    isSelected: viewModel.selectedNodeId == item.id,
                    onSelect: {
                        viewModel.selectedNodeId = item.id
                        viewModel.selectedResultIndex = -1
                    },
                    onOpen: { viewModel.openRecent(item) }
                )
                .id(item.id)
                .commandKCardContextMenu(atomUUID: item.id, entityId: item.entityId, atomType: item.type)
            }
        }
    }

    // MARK: Results (active query)

    @ViewBuilder
    private var resultsSections: some View {
        let groups = viewModel.unifiedGroupedResults.filter { !$0.results.isEmpty }
        if groups.isEmpty {
            railHint(viewModel.currentPhase == .searching ? "Searching…" : "No matches yet.")
        } else {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                AtelierOrnamentalSectionLabel(label: group.source.displayName.uppercased())
                ForEach(group.results) { result in
                    CortexRailRow(
                        title: result.title,
                        subtitle: result.subtitle ?? result.snippet ?? "",
                        accent: result.accentColor,
                        thumbnailURL: nil,
                        previewText: result.snippet ?? result.subtitle,
                        isConnection: result.atomType == .connection,
                        isSelected: viewModel.selectedNodeId == result.selectionID,
                        onSelect: { select(result) },
                        onOpen: { select(result); viewModel.openSelected() }
                    )
                    .id(result.selectionID)
                    .commandKSearchResultContextMenu(result: result)
                }
            }
        }
    }

    private func select(_ result: UnifiedSearchResult) {
        viewModel.selectedNodeId = result.selectionID
        viewModel.selectedResultIndex =
            viewModel.unifiedFlatResults.firstIndex { $0.selectionID == result.selectionID } ?? -1
    }

    private func railHint(_ text: String) -> some View {
        Text(text)
            .font(DS.dateSerif)
            .italic()
            .foregroundStyle(DS.inkFaded)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, DS.space24)
    }
}

private struct CortexRailRow: View {
    let title: String
    let subtitle: String
    let accent: Color
    let thumbnailURL: String?
    let previewText: String?
    let isConnection: Bool
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.space12) {
            thumbnail
                .frame(width: 38, height: 50)
                .clipShape(.rect(cornerRadius: DS.radiusSmall))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.radiusSmall, style: .continuous)
                        .strokeBorder(DS.sepiaSubtle, lineWidth: 0.5)
                )
            VStack(alignment: .leading, spacing: DS.space2) {
                Text(title)
                    .font(DS.callout)
                    .foregroundStyle(DS.text)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(DS.caption2)
                        .foregroundStyle(DS.inkFaded)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DS.space8)
        .background(rowBackground)
        .overlay(rowBorder)
        .clipShape(.rect(cornerRadius: DS.radiusMedium))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onOpen() }
        .onTapGesture { onSelect() }
        .onHover { hovering in
            withAnimation(ProMotionSprings.hover) { isHovered = hovering }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityHint("Double-tap or press return to open")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let url = thumbnailURL, !url.isEmpty {
            SpotlightImageContent(urlString: url)
        } else if isConnection {
            SpotlightConnectionPreview(preview: previewText, accentColor: accent)
        } else if let text = previewText, !text.isEmpty {
            SpotlightPageContent(text: text, accentColor: accent)
        } else {
            SpotlightFauxPage(accentColor: accent)
        }
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .fill(isSelected ? accent.opacity(0.10) : (isHovered ? DS.vellum : Color.clear))
    }

    private var rowBorder: some View {
        RoundedRectangle(cornerRadius: DS.radiusMedium, style: .continuous)
            .strokeBorder(
                isSelected ? accent.opacity(0.45) : (isHovered ? DS.sepiaSubtle : Color.clear),
                lineWidth: isSelected ? 1 : 0.5
            )
    }
}
