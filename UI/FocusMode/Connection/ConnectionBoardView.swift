// CosmoOS/UI/FocusMode/Connection/ConnectionBoardView.swift
// June 2026 — Connection workspace revamp.
// The center "Board": all 11 section cards in a masonry layout — each card
// keeps its natural height and packs into the shortest column in sortOrder,
// so cards of different sizes sit flush instead of leaving row-height gaps.
// Search filters cards, navigator clicks scroll to them.

import SwiftUI

struct ConnectionBoardView: View {
    var viewModel: ConnectionFocusModeViewModel
    var workspace: ConnectionWorkspaceModel
    let actions: ConnectionWorkspaceActions

    private var visibleSections: [ConnectionSection] {
        workspace.matchingSections(in: viewModel.state.sections)
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    /// Repack the masonry whenever the set of cards or their content volume
    /// changes — filtering, adding/editing items, ghosts arriving.
    private var layoutFingerprint: [String] {
        visibleSections.map { "\($0.type.rawValue):\($0.items.count):\($0.ghostSuggestions.count)" }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                boardContent
                    .padding(.horizontal, DS.space24)
                    .padding(.top, DS.space16)
                    .padding(.bottom, DS.space48)
            }
            .scrollIndicators(.automatic)
            .onChange(of: workspace.scrollTarget) { _, target in
                guard let target else { return }
                withAnimation(ProMotionSprings.gentle) {
                    proxy.scrollTo(target.rawValue, anchor: .top)
                }
                workspace.scrollTarget = nil
            }
        }
    }

    @ViewBuilder
    private var boardContent: some View {
        if visibleSections.isEmpty {
            noResults
        } else {
            masonry
        }
    }

    private var masonry: some View {
        ConnectionMasonryLayout(spacing: DS.space16) {
            ForEach(visibleSections) { section in
                sectionCard(section)
                    .id(section.type.rawValue)
            }
        }
        .animation(ProMotionSprings.gentle, value: layoutFingerprint)
    }

    private func sectionCard(_ section: ConnectionSection) -> some View {
        ConnectionSectionCardView(
            section: section,
            isSelected: workspace.selection == .section(section.type),
            highlightQuery: workspace.searchQuery,
            onOpen: { workspace.openSection(section.type) },
            onSelect: { workspace.selection = .section(section.type) },
            onAddItem: { document, text in
                viewModel.addItem(document: document, plainText: text, toSection: section.type)
            },
            onAcceptGhost: { ghost in viewModel.acceptGhost(ghost, inSection: section.type) },
            onDismissGhost: { id in viewModel.dismissGhost(id, inSection: section.type) },
            onSourceTap: actions.onSourceTap
        )
    }

    private var noResults: some View {
        VStack(spacing: DS.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24))
                .foregroundStyle(DS.textMuted)
                .accessibilityHidden(true)
            Text("Nothing matches “\(workspace.searchQuery)”")
                .font(DS.headline)
                .foregroundStyle(DS.text)
            Text("Try a different term, or clear the search to see every section.")
                .font(DS.callout)
                .foregroundStyle(DS.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.space48)
    }
}

// MARK: - Masonry layout

/// Pinterest-style column packing: subviews are measured at column width and
/// placed, in order, into the currently-shortest column (leftmost on ties),
/// so every card keeps its intrinsic height and columns stay flush. Exact —
/// no height estimation — and cheap at this board's card count.
struct ConnectionMasonryLayout: Layout {
    var spacing: CGFloat = DS.space16
    var minColumnWidth: CGFloat = 290
    var maxColumns: Int = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = resolvedWidth(from: proposal)
        let frames = frames(forWidth: width, subviews: subviews)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let frames = frames(forWidth: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    /// SwiftUI probes layouts with nil and `.infinity` width proposals during
    /// measurement — answer those with the layout's ideal width (all columns
    /// at minimum width) instead of letting non-finite math reach `Int(...)`.
    func resolvedWidth(from proposal: ProposedViewSize) -> CGFloat {
        guard let proposed = proposal.width, proposed.isFinite else {
            return CGFloat(maxColumns) * minColumnWidth + spacing * CGFloat(maxColumns - 1)
        }
        return max(proposed, minColumnWidth)
    }

    func columnCount(forWidth width: CGFloat) -> Int {
        guard width.isFinite, width > 0 else { return 1 }
        let fit = Int((width + spacing) / (minColumnWidth + spacing))
        return max(1, min(maxColumns, fit))
    }

    private func frames(forWidth width: CGFloat, subviews: Subviews) -> [CGRect] {
        let columns = columnCount(forWidth: width)
        let columnWidth = (width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        var columnHeights = [CGFloat](repeating: 0, count: columns)
        var frames: [CGRect] = []
        frames.reserveCapacity(subviews.count)

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil))
            let column = columnHeights.indices.min {
                (columnHeights[$0], $0) < (columnHeights[$1], $1)
            } ?? 0
            frames.append(CGRect(
                x: CGFloat(column) * (columnWidth + spacing),
                y: columnHeights[column],
                width: columnWidth,
                height: size.height
            ))
            columnHeights[column] += size.height + spacing
        }
        return frames
    }
}
