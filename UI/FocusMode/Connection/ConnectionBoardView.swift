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
    var pendingInsertsBySection: [ConnectionSectionType: [ConnectionPendingInsert]] = [:]

    private var visibleSections: [ConnectionSection] {
        workspace.matchingSections(in: viewModel.state.sections)
            .sorted { $0.type.sortOrder < $1.type.sortOrder }
    }

    /// Repack the masonry whenever the set of cards or their content volume
    /// changes — filtering, adding/editing items, or staged inserts arriving.
    private var layoutFingerprint: [String] {
        var prints = visibleSections.map {
            "\($0.type.rawValue):\($0.items.count):\(pendingInsertsBySection[$0.type]?.count ?? 0)"
        }
        prints.append("handlings:\(workspace.stagedObjectionHandlings.count)")
        prints.append("gallery:\(showsGallery ? viewModel.state.media.count : -1):\(workspace.pendingMediaCaptures):\(workspace.stagedMediaAtoms.count)")
        return prints
    }

    /// The Gallery card shows whenever media exists (or a drag could land) and
    /// the search isn't filtering it out. Query matches against captions and
    /// source titles so gallery media is findable like item text.
    private var showsGallery: Bool {
        let query = workspace.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        if "gallery".localizedCaseInsensitiveContains(query) { return true }
        return viewModel.state.media.contains { item in
            if let caption = item.caption, caption.localizedCaseInsensitiveContains(query) { return true }
            if let uuid = item.atomUUID,
               let title = viewModel.mediaAtoms[uuid]?.title,
               title.localizedCaseInsensitiveContains(query) { return true }
            if let title = item.assetTitle, title.localizedCaseInsensitiveContains(query) { return true }
            return false
        }
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
            // Finder files and browser URLs dropped anywhere on the board:
            // media files become owned assets, http(s) URLs run the capture
            // pipeline. Atom-ref drags hit the gallery/section targets instead
            // (different payload type — no conflict).
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter { $0.isFileURL && MediaAssetStore.isSupportedMediaExtension($0.pathExtension) }
                let webURLs = urls.filter { !$0.isFileURL }
                guard !files.isEmpty || !webURLs.isEmpty else { return false }
                if !files.isEmpty { actions.onDropMediaFiles(files, nil) }
                for web in webURLs { actions.onPasteMediaURL(web.absoluteString, nil) }
                return true
            }
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
                    .opacity(isDimmed(section) ? 0.3 : 1)
                    .id(section.type.rawValue)
            }
            if showsGallery {
                ConnectionGalleryCard(
                    media: viewModel.state.orderedMedia,
                    atoms: viewModel.mediaAtoms,
                    pendingCaptureCount: workspace.pendingMediaCaptures,
                    stagedAtoms: workspace.stagedMediaAtoms,
                    compareSelection: workspace.compareSelection,
                    actions: actions
                )
                .opacity(workspace.focusedSection == nil ? 1 : 0.3)
                .id("gallery")
            }
        }
        .animation(ProMotionSprings.gentle, value: layoutFingerprint)
        .animation(ProMotionSprings.gentle, value: workspace.focusedSection)
    }

    /// True while another section is spotlighted from the navigator.
    private func isDimmed(_ section: ConnectionSection) -> Bool {
        guard let focused = workspace.focusedSection else { return false }
        return focused != section.type
    }

    private func sectionCard(_ section: ConnectionSection) -> some View {
        ConnectionSectionCardView(
            section: section,
            isSelected: workspace.selection == .section(section.type),
            highlightQuery: workspace.searchQuery,
            pendingInserts: pendingInsertsBySection[section.type] ?? [],
            anchoredMedia: viewModel.state.media(anchoredTo: section.type),
            mediaAtoms: viewModel.mediaAtoms,
            stagedHandlings: section.type == .beliefsObjections ? workspace.stagedObjectionHandlings : [],
            resolveBoardRef: { viewModel.resolveBoardRef($0) },
            onOpen: { workspace.openSection(section.type) },
            onSelect: { workspace.selection = .section(section.type) },
            onAddItem: { document, text in
                viewModel.addItem(document: document, plainText: text, toSection: section.type)
            },
            onSourceTap: actions.onSourceTap,
            onAcceptInsert: actions.onAcceptInsert,
            onRejectInsert: actions.onRejectInsert,
            mediaActions: actions
        )
        .dropDestination(for: AtomDragPayload.self) { payloads, _ in
            guard !payloads.isEmpty else { return false }
            actions.onDropMediaAtoms(payloads.map(\.atomUUID), section.type)
            return true
        }
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
